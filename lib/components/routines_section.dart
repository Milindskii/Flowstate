import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/routine.dart';
import '../services/routine_service.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';
import 'day_path/stop_emoji.dart';
import 'noya_companion_view.dart';
import 'noya_notice.dart';

/// Insights > Routines: the user's recurring weekly routines ("Gym · Mon · Wed · Fri · 7:00 PM").
///
/// Create, edit (days, time, duration) and remove, all through the one routine backend. A routine plans one confirmed
/// week at a time; when that week ends Noya asks "Continue your routine next week?" (once per cycle on this device,
/// and inline here until it is answered). Nothing here is AI and nothing costs a Shield.
class RoutinesSection extends StatefulWidget {
  final RoutineService service;

  /// Ask the weekly continuation question in a Noya dialog when a cycle is due (once per routine and cycle).
  final bool autoAsk;

  const RoutinesSection({super.key, required this.service, this.autoAsk = true});

  @override
  State<RoutinesSection> createState() => _RoutinesSectionState();
}

class _RoutinesSectionState extends State<RoutinesSection> {
  List<Routine>? _routines;
  bool _failed = false;
  final Set<String> _busy = {};

  /// Cycles already answered on this screen: a late second tap on a prompt that has not redrawn yet sends nothing.
  final Set<String> _answered = {};

  @override
  void initState() {
    super.initState();
    _load(ask: widget.autoAsk);
  }

  Future<void> _load({bool ask = false}) async {
    try {
      final list = await widget.service.list();
      if (!mounted) return;
      setState(() {
        _routines = list;
        _failed = false;
      });
      if (ask) await _askDueOnce(list);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  static String askedKey(Routine r) => 'routine_continue_asked_${r.id}_${r.cycleEndParam}';

  /// The Noya question pops up once per routine and cycle; afterwards it waits inline in this section.
  Future<void> _askDueOnce(List<Routine> list) async {
    for (final r in list.where((r) => r.continuationDue)) {
      SharedPreferences? prefs;
      try {
        prefs = await SharedPreferences.getInstance();
        if (prefs.getBool(askedKey(r)) ?? false) continue;
        await prefs.setBool(askedKey(r), true);
      } catch (_) {}
      if (!mounted) return;
      final proceed = await showRoutineContinuationDialog(context, r);
      if (proceed == null || !mounted) continue; // dismissed: the inline prompt stays
      await _answer(r, proceed: proceed);
    }
  }

  Future<void> _answer(Routine r, {required bool proceed}) async {
    final cycle = '${r.id}_${r.cycleEndParam}_$proceed';
    if (_busy.contains(r.id) || _answered.contains(cycle)) return; // a double tap never sends two answers
    _answered.add(cycle);
    setState(() => _busy.add(r.id));
    try {
      final planned = await widget.service.answerContinuation(r, proceed: proceed);
      if (proceed) {
        NoyaNoticeCenter.instance.success(
            planned > 0 ? '${r.title} is planned for next week.' : '${r.title} continues next week.',
            title: 'Routine continued');
      } else {
        NoyaNoticeCenter.instance.info('${r.title} is paused. You can continue it here anytime.');
      }
      await _load();
    } catch (_) {
      _answered.remove(cycle); // nothing was recorded: the question can be answered again
      NoyaNoticeCenter.instance.failure("Couldn't update ${r.title}. Try again.");
    } finally {
      if (mounted) setState(() => _busy.remove(r.id));
    }
  }

  Future<void> _edit([Routine? r]) async {
    final draft = await showRoutineEditorSheet(context, routine: r);
    if (draft == null || !mounted) return;
    final key = r?.id ?? 'new';
    setState(() => _busy.add(key));
    try {
      if (r == null) {
        await widget.service.create(
          title: draft.title,
          weekdays: draft.weekdays,
          startHhmm: draft.startHhmm,
          estimatedMinutes: draft.minutes,
          idempotencyKey: draft.idempotencyKey,
        );
        NoyaNoticeCenter.instance.success('${draft.title} will be planned this week.', title: 'Routine saved');
      } else {
        await widget.service.update(r.id,
            title: draft.title, weekdays: draft.weekdays, startHhmm: draft.startHhmm, estimatedMinutes: draft.minutes);
        NoyaNoticeCenter.instance.success('Upcoming days follow the new plan. Past days stay as they were.',
            title: 'Routine updated');
      }
      FlowHaptics.selection();
      await _load();
    } catch (_) {
      NoyaNoticeCenter.instance.failure("Couldn't save ${draft.title}. Try again.");
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Future<void> _remove(Routine r) async {
    if (_busy.contains(r.id)) return;
    setState(() => _busy.add(r.id));
    try {
      await widget.service.delete(r.id);
      FlowHaptics.lightTap();
      NoyaNoticeCenter.instance.info('${r.title} removed. Past days stay in your history.');
      await _load();
    } catch (_) {
      NoyaNoticeCenter.instance.failure("Couldn't remove ${r.title}. Try again.");
    } finally {
      if (mounted) setState(() => _busy.remove(r.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final routines = _routines;
    final accent = Theme.of(context).colorScheme.primary;
    final muted = FlowColors.textSecondaryOf(context);
    return Column(
      key: const Key('insights_routines_manager'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Routines',
                  style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context))
                      .copyWith(fontWeight: FontWeight.w700)),
            ),
            TextButton.icon(
              key: const Key('routine_add_button'),
              onPressed: _busy.contains('new') ? null : () => _edit(),
              style: TextButton.styleFrom(foregroundColor: accent),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add'),
            ),
          ],
        ),
        Text('Weekly habits Flowstate plans for you, one week at a time.',
            style: FlowTypography.bodySmall(color: muted)),
        const SizedBox(height: 10),
        if (_failed)
          Text("Couldn't load your routines right now.", style: FlowTypography.bodyMedium(color: muted))
        else if (routines == null)
          const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
        else if (routines.isEmpty)
          Text('No routines yet. Add one, like "Gym · Mon · Wed · Fri · 7:00 PM".',
              key: const Key('routines_empty'), style: FlowTypography.bodyMedium(color: muted))
        else
          for (final r in routines) _RoutineRow(
            routine: r,
            busy: _busy.contains(r.id),
            onEdit: r.createsTasks ? () => _edit(r) : null,
            onRemove: () => _remove(r),
            onContinue: () => _answer(r, proceed: true),
            onNotNow: () => _answer(r, proceed: false),
          ),
      ],
    );
  }
}

class _RoutineRow extends StatelessWidget {
  final Routine routine;
  final bool busy;
  final VoidCallback? onEdit;
  final VoidCallback onRemove;
  final VoidCallback onContinue;
  final VoidCallback onNotNow;

  const _RoutineRow({
    required this.routine,
    required this.busy,
    required this.onEdit,
    required this.onRemove,
    required this.onContinue,
    required this.onNotNow,
  });

  @override
  Widget build(BuildContext context) {
    final r = routine;
    final muted = FlowColors.textSecondaryOf(context);
    final accent = Theme.of(context).colorScheme.primary;
    final meta = [r.daysLabel, if (r.timeLabel.isNotEmpty) r.timeLabel, '${r.estimatedMinutes} min'].join(' · ');
    return Container(
      key: Key('routine_tile_${r.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: FlowColors.surfaceElevated(context),
        borderRadius: FlowRadii.cardRadius,
        border: Border.all(color: FlowColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: FlowRadii.cardRadius,
            onTap: busy ? null : onEdit,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
              child: Row(
                children: [
                  Icon(stopIconFor(title: r.title), size: 22, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FlowTypography.bodyLarge(color: FlowColors.textPrimaryOf(context))
                                .copyWith(fontWeight: FontWeight.w600)),
                        Text(meta,
                            key: Key('routine_meta_${r.id}'),
                            style: FlowTypography.bodySmall(color: muted)),
                        if (r.paused)
                          Text('Paused', style: FlowTypography.labelSmall(color: muted).copyWith(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  IconButton(
                    key: Key('routine_delete_${r.id}'),
                    tooltip: 'Remove routine',
                    icon: const Icon(Icons.delete_outline_rounded, size: 20),
                    color: muted,
                    onPressed: busy ? null : onRemove,
                  ),
                ],
              ),
            ),
          ),
          if (r.continuationDue || r.paused)
            Padding(
              key: Key('routine_continue_prompt_${r.id}'),
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(r.paused ? 'Plan it again from this week?' : 'Continue next week?',
                        style: FlowTypography.bodySmall(color: FlowColors.textPrimaryOf(context))),
                  ),
                  if (!r.paused)
                    TextButton(
                      key: Key('routine_not_now_${r.id}'),
                      onPressed: busy ? null : onNotNow,
                      child: const Text('Not now'),
                    ),
                  FilledButton(
                    key: Key('routine_continue_${r.id}'),
                    style: FilledButton.styleFrom(backgroundColor: accent, visualDensity: VisualDensity.compact),
                    onPressed: busy ? null : onContinue,
                    child: const Text('Continue'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Noya asks once per weekly cycle. Returns true (Continue), false (Not now) or null (dismissed: asked again inline).
Future<bool?> showRoutineContinuationDialog(BuildContext context, Routine r) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('routine_continue_dialog'),
      backgroundColor: FlowColors.surface(ctx),
      shape: const RoundedRectangleBorder(borderRadius: FlowRadii.cardLargeRadius),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const NoyaCompanionView(state: NoyaState.encouraging, size: 64),
          const SizedBox(height: 12),
          Text('Continue your routine next week?',
              textAlign: TextAlign.center,
              style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(ctx)).copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('${r.title} · ${[r.daysLabel, if (r.timeLabel.isNotEmpty) r.timeLabel].join(' · ')}',
              textAlign: TextAlign.center, style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(ctx))),
        ],
      ),
      actions: [
        TextButton(
            key: const Key('routine_dialog_not_now'), onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Not now')),
        FilledButton(
            key: const Key('routine_dialog_continue'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Continue')),
      ],
    ),
  );
}

/// What the routine editor returns.
class RoutineDraft {
  final String title;
  final List<int> weekdays;
  final String startHhmm;
  final int minutes;
  final String idempotencyKey;
  const RoutineDraft({
    required this.title,
    required this.weekdays,
    required this.startHhmm,
    required this.minutes,
    required this.idempotencyKey,
  });
}

/// Create or edit a routine: a name, the weekdays, a time and a duration. Simple controls, no AI.
Future<RoutineDraft?> showRoutineEditorSheet(BuildContext context, {Routine? routine}) {
  return showModalBottomSheet<RoutineDraft>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: FlowColors.surface(context),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(FlowRadii.cardLarge))),
    builder: (_) => _RoutineEditor(routine: routine),
  );
}

class _RoutineEditor extends StatefulWidget {
  final Routine? routine;
  const _RoutineEditor({this.routine});

  @override
  State<_RoutineEditor> createState() => _RoutineEditorState();
}

class _RoutineEditorState extends State<_RoutineEditor> {
  late final TextEditingController _title = TextEditingController(text: widget.routine?.title ?? '');
  late final Set<int> _days = {
    ...(widget.routine == null
        ? const <int>[]
        : (widget.routine!.recurrence == 'weekly' ? widget.routine!.weekdays : const [0, 1, 2, 3, 4, 5, 6]))
  };
  late TimeOfDay _time = () {
    final hhmm = widget.routine?.startHhmm;
    if (hhmm == null || hhmm.length < 5) return const TimeOfDay(hour: 19, minute: 0);
    return TimeOfDay(hour: int.tryParse(hhmm.substring(0, 2)) ?? 19, minute: int.tryParse(hhmm.substring(3, 5)) ?? 0);
  }();
  late int _minutes = widget.routine?.estimatedMinutes ?? 60;
  // stable for this editor: a double tap on Save can never create the routine twice
  final String _key = 'manual-${DateTime.now().microsecondsSinceEpoch}';

  static const _durations = [15, 30, 45, 60, 90, 120];

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  bool get _valid => _title.text.trim().isNotEmpty && _days.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final primary = FlowColors.textPrimaryOf(context);
    final muted = FlowColors.textSecondaryOf(context);
    final accent = Theme.of(context).colorScheme.primary;
    final hhmm = '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        key: const Key('routine_editor'),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.routine == null ? 'New routine' : 'Edit routine',
                style: FlowTypography.titleMedium(color: primary).copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
              key: const Key('routine_title_field'),
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Name', hintText: 'Gym'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            Text('Days', style: FlowTypography.labelMedium(color: muted)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var d = 0; d < 7; d++)
                  FilterChip(
                    key: Key('routine_day_$d'),
                    label: Text(Routine.dayNames[d]),
                    selected: _days.contains(d),
                    showCheckmark: false,
                    onSelected: (on) => setState(() => on ? _days.add(d) : _days.remove(d)),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('routine_time_button'),
                    icon: const Icon(Icons.schedule_rounded, size: 18),
                    label: Text(_time.format(context)),
                    onPressed: () async {
                      final picked = await showTimePicker(context: context, initialTime: _time);
                      if (picked != null) setState(() => _time = picked);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    key: const Key('routine_duration_field'),
                    initialValue: _durations.contains(_minutes) ? _minutes : 60,
                    decoration: const InputDecoration(labelText: 'Duration', isDense: true),
                    items: [for (final m in _durations) DropdownMenuItem(value: m, child: Text('$m min'))],
                    onChanged: (v) => setState(() => _minutes = v ?? _minutes),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('routine_save_button'),
                style: FilledButton.styleFrom(backgroundColor: accent),
                onPressed: _valid
                    ? () => Navigator.of(context).pop(RoutineDraft(
                          title: _title.text.trim(),
                          weekdays: (_days.toList()..sort()),
                          startHhmm: hhmm,
                          minutes: _minutes,
                          idempotencyKey: _key,
                        ))
                    : null,
                child: Text(widget.routine == null ? 'Save routine' : 'Save changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
