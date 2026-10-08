import 'package:flutter/material.dart';
import '../models/routine.dart';
import '../services/api_service.dart';
import '../services/routine_service.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_typography.dart';

/// "My routines": view, retime or delete saved routines. Edits and deletes only affect future occurrences.
Future<void> showRoutinesSheet(BuildContext context, ApiService api) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: FlowColors.surface(context),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => RoutinesSheet(service: RoutineService(api: api)),
  );
}

class RoutinesSheet extends StatefulWidget {
  final RoutineService service;
  const RoutinesSheet({super.key, required this.service});

  @override
  State<RoutinesSheet> createState() => _RoutinesSheetState();
}

class _RoutinesSheetState extends State<RoutinesSheet> {
  List<Routine>? _routines;
  bool _failed = false;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await widget.service.list();
      if (mounted) setState(() => _routines = list);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _retime(Routine r) async {
    if (_busy.contains(r.id)) return;
    final parts = (r.startHhmm ?? '09:00').split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.tryParse(parts[0]) ?? 9, minute: int.tryParse(parts[1]) ?? 0),
    );
    if (picked == null || !mounted) return;
    final hhmm = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() => _busy.add(r.id));
    try {
      await widget.service.update(r.id, startHhmm: hhmm);
      FlowHaptics.selection();
      await _load();
    } catch (_) {
      _snack("Couldn't update ${r.title}. Please try again.");
    } finally {
      if (mounted) setState(() => _busy.remove(r.id));
    }
  }

  Future<void> _delete(Routine r) async {
    if (_busy.contains(r.id)) return;
    setState(() => _busy.add(r.id));
    try {
      await widget.service.delete(r.id);
      FlowHaptics.lightTap();
      await _load();
    } catch (_) {
      _snack("Couldn't remove ${r.title}. Please try again.");
    } finally {
      if (mounted) setState(() => _busy.remove(r.id));
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final routines = _routines;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Routines',
                style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context))
                    .copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              'Changes apply to upcoming days only. Past days are never rewritten.',
              style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)),
            ),
            const SizedBox(height: 12),
            if (_failed)
              Text("Couldn't load your routines right now.",
                  style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)))
            else if (routines == null)
              const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
            else if (routines.isEmpty)
              Text(
                'No routines yet. Tell Noya about one in Build My Day, like "I go to the gym every day at 4 PM".',
                key: const Key('routines_empty'),
                style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)),
              )
            else
              for (final r in routines)
                ListTile(
                  key: Key('routine_tile_${r.id}'),
                  contentPadding: EdgeInsets.zero,
                  minTileHeight: 56,
                  title: Text(r.title,
                      style: FlowTypography.bodyLarge(color: FlowColors.textPrimaryOf(context))),
                  subtitle: Text(r.summary,
                      style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context))),
                  onTap: r.kind == 'fixed' || r.kind == 'preferred' ? () => _retime(r) : null,
                  trailing: IconButton(
                    key: Key('routine_delete_${r.id}'),
                    tooltip: 'Remove routine',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: _busy.contains(r.id) ? null : () => _delete(r),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
