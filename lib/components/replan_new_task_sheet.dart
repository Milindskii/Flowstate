import 'package:flutter/material.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';
import 'primary_button.dart';

/// What the user entered for a new Replan task.
class ReplanNewTaskResult {
  final String title;
  final int minutes;
  final TimeOfDay? time;
  const ReplanNewTaskResult({required this.title, required this.minutes, this.time});
}

/// Small sheet to name a new task (Replan "Urgent work arrived") or to edit one in the preview before Apply.
class ReplanNewTaskSheet extends StatefulWidget {
  final String initialTitle;
  final int initialMinutes;
  final TimeOfDay? initialTime;
  final bool editing;

  const ReplanNewTaskSheet({
    super.key,
    this.initialTitle = '',
    this.initialMinutes = 45,
    this.initialTime,
    this.editing = false,
  });

  static Future<ReplanNewTaskResult?> show(
    BuildContext context, {
    String initialTitle = '',
    int initialMinutes = 45,
    TimeOfDay? initialTime,
    bool editing = false,
  }) {
    return showModalBottomSheet<ReplanNewTaskResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: FlowColors.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(FlowRadii.cardLarge)),
      ),
      builder: (_) => ReplanNewTaskSheet(
        initialTitle: initialTitle,
        initialMinutes: initialMinutes,
        initialTime: initialTime,
        editing: editing,
      ),
    );
  }

  @override
  State<ReplanNewTaskSheet> createState() => _ReplanNewTaskSheetState();
}

class _ReplanNewTaskSheetState extends State<ReplanNewTaskSheet> {
  static const _presets = [15, 30, 45, 60, 90];
  late final TextEditingController _title = TextEditingController(text: widget.initialTitle);
  late int _minutes = widget.initialMinutes;
  late TimeOfDay? _time = widget.initialTime;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  bool get _valid => _title.text.trim().isNotEmpty && _minutes >= 5 && _minutes <= 480;

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time ?? TimeOfDay.now());
    if (picked != null) setState(() => _time = picked);
  }

  void _submit() {
    if (!_valid) return;
    FlowHaptics.selection();
    Navigator.of(context).pop(ReplanNewTaskResult(title: _title.text.trim(), minutes: _minutes, time: _time));
  }

  @override
  Widget build(BuildContext context) {
    final muted = FlowColors.textSecondaryOf(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.editing ? 'Edit task' : 'What came up?',
                style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context))
                    .copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('replan_new_task_title'),
                controller: _title,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 120,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(hintText: 'e.g. Finish API security testing', counterText: ''),
              ),
              const SizedBox(height: 12),
              Text('DURATION', style: FlowTypography.labelSmall(color: muted).copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in _presets)
                    ChoiceChip(
                      key: Key('replan_new_task_min_$m'),
                      label: Text('$m min'),
                      selected: _minutes == m,
                      onSelected: (_) => setState(() => _minutes = m),
                    ),
                  if (!_presets.contains(_minutes)) ChoiceChip(label: Text('$_minutes min'), selected: true, onSelected: (_) {}),
                ],
              ),
              const SizedBox(height: 12),
              Text('START AT (OPTIONAL)',
                  style: FlowTypography.labelSmall(color: muted).copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Row(
                children: [
                  OutlinedButton.icon(
                    key: const Key('replan_new_task_time'),
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule_rounded, size: 16),
                    label: Text(_time == null ? 'Let Noya pick a time' : _time!.format(context)),
                  ),
                  if (_time != null)
                    IconButton(
                      tooltip: 'Clear time',
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => setState(() => _time = null),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                key: const Key('replan_new_task_submit'),
                label: widget.editing ? 'Save changes' : 'Plan it',
                onPressed: _valid ? _submit : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
