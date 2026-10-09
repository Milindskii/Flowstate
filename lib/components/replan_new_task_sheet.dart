import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../engines/scheduling_engine.dart';
import '../providers/theme_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';

/// What the user entered for a new Replan task.
class ReplanNewTaskResult {
  final String title;
  final int minutes;
  final TimeOfDay? time;
  final bool isNoyaPick;
  final String? explanation;

  const ReplanNewTaskResult({
    required this.title,
    required this.minutes,
    this.time,
    this.isNoyaPick = false,
    this.explanation,
  });
}

/// Sheet to name a new task (Replan "Urgent work arrived") or to edit one in preview before Apply.
class ReplanNewTaskSheet extends StatefulWidget {
  final String initialTitle;
  final int initialMinutes;
  final TimeOfDay? initialTime;
  final bool editing;
  final DateTime? selectedDate;
  final List<MapEntry<DateTime, DateTime>>? existingBusy;
  final PlanningProfile? planningProfile;

  const ReplanNewTaskSheet({
    super.key,
    this.initialTitle = '',
    this.initialMinutes = 45,
    this.initialTime,
    this.editing = false,
    this.selectedDate,
    this.existingBusy,
    this.planningProfile,
  });

  static Future<ReplanNewTaskResult?> show(
    BuildContext context, {
    String initialTitle = '',
    int initialMinutes = 45,
    TimeOfDay? initialTime,
    bool editing = false,
    DateTime? selectedDate,
    List<MapEntry<DateTime, DateTime>>? existingBusy,
    PlanningProfile? planningProfile,
  }) {
    final isDark = FlowColors.isDark(context);
    return showModalBottomSheet<ReplanNewTaskResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: FlowColors.surface(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(
              color: isDark ? FlowColors.borderDark : FlowColors.borderLight.withValues(alpha: 0.8),
              width: 1.0,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
              blurRadius: 24,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: ReplanNewTaskSheet(
          initialTitle: initialTitle,
          initialMinutes: initialMinutes,
          initialTime: initialTime,
          editing: editing,
          selectedDate: selectedDate,
          existingBusy: existingBusy,
          planningProfile: planningProfile,
        ),
      ),
    );
  }

  @override
  State<ReplanNewTaskSheet> createState() => _ReplanNewTaskSheetState();
}

class _ReplanNewTaskSheetState extends State<ReplanNewTaskSheet> {
  static const _presets = [15, 30, 45, 60, 90];
  late final TextEditingController _title = TextEditingController(text: widget.initialTitle);
  late final FocusNode _titleFocus = FocusNode()..addListener(() => setState(() {}));
  late int _minutes = widget.initialMinutes;
  late TimeOfDay? _selectedTime = widget.initialTime;

  @override
  void dispose() {
    _title.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  bool get _valid {
    return _title.text.trim().isNotEmpty && _minutes >= 5 && _minutes <= 480;
  }

  Future<void> _pickTime() async {
    FlowHaptics.lightTap();
    final initial = _selectedTime ?? TimeOfDay.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked != null) {
      FlowHaptics.selection();
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  void _submit() {
    if (!_valid) return;
    FlowHaptics.selection();
    final timeStr = _selectedTime?.format(context);
    Navigator.of(context).pop(ReplanNewTaskResult(
      title: _title.text.trim(),
      minutes: _minutes,
      time: _selectedTime,
      isNoyaPick: _selectedTime == null,
      explanation: timeStr != null ? 'Starts at $timeStr (fixed time)' : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    Color accent = FlowColors.accentCyan;
    try {
      final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
      accent = themeProvider.resolveAccent(context);
    } catch (_) {}

    final isDark = FlowColors.isDark(context);
    final textPrimary = FlowColors.textPrimaryOf(context);
    final textSecondary = FlowColors.textSecondaryOf(context);
    final textMuted = FlowColors.textMutedOf(context);
    final inputBg = isDark ? FlowColors.surfaceContainer(context) : const Color(0xFFF8FAFC);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(top: 4, bottom: 16),
                  decoration: BoxDecoration(
                    color: FlowColors.border(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      widget.editing ? Icons.edit_note_rounded : Icons.bolt_rounded,
                      color: accent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.editing ? 'Edit task' : 'What came up?',
                          style: FlowTypography.titleMedium(color: textPrimary).copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.editing
                              ? 'Adjust details before applying'
                              : 'Add urgent work into your day',
                          style: FlowTypography.bodySmall(color: textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: textSecondary,
                    tooltip: 'Close',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Title input card
              Container(
                decoration: BoxDecoration(
                  color: inputBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _titleFocus.hasFocus ? accent : FlowColors.border(context),
                    width: _titleFocus.hasFocus ? 1.5 : 1.0,
                  ),
                  boxShadow: _titleFocus.hasFocus
                      ? [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.12),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: _titleFocus.hasFocus ? accent : textMuted,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        key: const Key('replan_new_task_title'),
                        controller: _title,
                        focusNode: _titleFocus,
                        autofocus: true,
                        textCapitalization: TextCapitalization.sentences,
                        maxLength: 120,
                        style: FlowTypography.bodyLarge(color: textPrimary).copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          hintText: 'e.g. Urgent review, fix critical bug...',
                          hintStyle: FlowTypography.bodyMedium(color: textMuted),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          counterText: '',
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    if (_title.text.isNotEmpty)
                      GestureDetector(
                        onTap: () => setState(() => _title.clear()),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(Icons.cancel_rounded, size: 16, color: textMuted),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Duration section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.timer_outlined, size: 14, color: textSecondary),
                      const SizedBox(width: 6),
                      Text(
                        'Duration',
                        style: FlowTypography.labelMedium(color: textPrimary).copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$_minutes min',
                      style: FlowTypography.labelSmall(color: accent).copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in _presets)
                    _buildDurationChip(
                      key: Key('replan_new_task_min_$m'),
                      label: '$m min',
                      isSelected: _minutes == m,
                      accent: accent,
                      onTap: () {
                        FlowHaptics.selection();
                        setState(() => _minutes = m);
                      },
                    ),
                  if (!_presets.contains(_minutes))
                    _buildDurationChip(
                      label: '$_minutes min',
                      isSelected: true,
                      accent: accent,
                      onTap: () {},
                    ),
                ],
              ),
              const SizedBox(height: 18),

              // Start time section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.schedule_rounded, size: 14, color: textSecondary),
                      const SizedBox(width: 6),
                      Text(
                        'Start time',
                        style: FlowTypography.labelMedium(color: textPrimary).copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  if (_selectedTime != null)
                    Text(
                      'Fixed time',
                      style: FlowTypography.labelSmall(
                        color: FlowColors.accentAmber,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                ],
              ),
              const SizedBox(height: 10),

              // Time selector card
              Material(
                key: const Key('replan_new_task_time'),
                color: _selectedTime != null
                    ? accent.withValues(alpha: 0.08)
                    : (isDark ? FlowColors.surfaceContainer(context) : const Color(0xFFF8FAFC)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: _selectedTime != null
                        ? accent.withValues(alpha: 0.45)
                        : FlowColors.border(context),
                    width: 1.0,
                  ),
                ),
                child: InkWell(
                  onTap: _pickTime,
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: _selectedTime != null
                                ? accent.withValues(alpha: 0.16)
                                : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            _selectedTime != null
                                ? Icons.lock_clock_rounded
                                : Icons.schedule_rounded,
                            size: 16,
                            color: _selectedTime != null ? accent : textSecondary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedTime != null
                                    ? 'Starts at ${_selectedTime!.format(context)}'
                                    : 'Pick a time',
                                style: FlowTypography.bodyMedium(
                                  color: _selectedTime != null ? textPrimary : textSecondary,
                                ).copyWith(
                                  fontWeight: _selectedTime != null ? FontWeight.w600 : FontWeight.w500,
                                ),
                              ),
                              if (_selectedTime != null) ...[
                                const SizedBox(height: 1),
                                Text(
                                  'Fixed time selected by you',
                                  style: FlowTypography.bodySmall(
                                    color: textMuted,
                                  ).copyWith(fontSize: 12),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (_selectedTime != null)
                          IconButton(
                            key: const Key('replan_new_task_clear_time'),
                            tooltip: 'Clear selected time',
                            icon: Icon(Icons.close_rounded, size: 18, color: textSecondary),
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              FlowHaptics.selection();
                              setState(() {
                                _selectedTime = null;
                              });
                            },
                          )
                        else
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: textMuted,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),

              // Submit button
              _buildSubmitButton(accent: accent, isDark: isDark),
              const SizedBox(height: 10),

              // Reassuring micro-copy
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                     Icon(Icons.shield_outlined, size: 12, color: textMuted),
                    const SizedBox(width: 5),
                    Text(
                      'Existing commitments stay protected',
                      style: FlowTypography.bodySmall(color: textMuted).copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDurationChip({
    Key? key,
    required String label,
    required bool isSelected,
    required Color accent,
    required VoidCallback onTap,
  }) {
    final isDark = FlowColors.isDark(context);
    final chipBg = isSelected
        ? accent.withValues(alpha: 0.14)
        : (isDark ? FlowColors.surfaceContainer(context) : FlowColors.surfaceElevated(context));
    final borderColor = isSelected ? accent : FlowColors.border(context);
    final labelColor = isSelected ? accent : FlowColors.textSecondaryOf(context);

    return Material(
      key: key,
      color: chipBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: isSelected ? 1.5 : 1.0),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: FlowTypography.labelMedium(color: labelColor).copyWith(
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubmitButton({required Color accent, required bool isDark}) {
    final enabled = _valid;
    final btnBg = enabled
        ? accent
        : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0));
    final btnTextColor = enabled
        ? Colors.white
        : (isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8));

    final String buttonText = widget.editing ? 'Save changes' : 'Plan it';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: double.infinity,
      height: 50,
      decoration: BoxDecoration(
        color: btnBg,
        borderRadius: FlowRadii.buttonRadius,
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.28),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('replan_new_task_submit'),
          onTap: enabled ? _submit : null,
          borderRadius: FlowRadii.buttonRadius,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.editing ? Icons.check_circle_outline_rounded : Icons.auto_awesome_rounded,
                  size: 18,
                  color: btnTextColor,
                ),
                const SizedBox(width: 8),
                Text(
                  buttonText,
                  style: FlowTypography.labelLarge(color: btnTextColor).copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

