import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/flow_haptics.dart';

/// Flowstate Clean & Focused Circadian Time Control with Circular Timer Loading
///
/// Refinements:
/// - Excess preset time chips and redundant text completely removed
/// - Focus is 100% on the Clock and Time
/// - Compact, sleek AM / PM toggle integrated cleanly with the digital readout
/// - Circular Timer Loading Arc: glowing arc sweeps around the clock dial perimeter
///   providing an authentic, tactile circular timer experience
class FlowTimePicker extends StatefulWidget {
  final String initialTime24; // e.g. "07:00"
  final ValueChanged<String> onTimeChanged;
  final bool isWakeTime;

  const FlowTimePicker({
    super.key,
    required this.initialTime24,
    required this.onTimeChanged,
    this.isWakeTime = true,
  });

  @override
  State<FlowTimePicker> createState() => _FlowTimePickerState();
}

class _FlowTimePickerState extends State<FlowTimePicker> with SingleTickerProviderStateMixin {
  late int _hour; // 1 - 12
  late int _minute; // 0 - 59
  late bool _isAm;
  bool _selectingHours = true;
  bool _isTypingMode = false;

  late TextEditingController _hourController;
  late TextEditingController _minuteController;
  final FocusNode _hourFocus = FocusNode();
  final FocusNode _minuteFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _parseInitialTime();
    _hourController = TextEditingController(text: _hour.toString().padLeft(2, '0'));
    _minuteController = TextEditingController(text: _minute.toString().padLeft(2, '0'));
  }

  @override
  void didUpdateWidget(covariant FlowTimePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTime24 != widget.initialTime24) {
      _parseInitialTime();
      _syncControllers();
    }
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    _hourFocus.dispose();
    _minuteFocus.dispose();
    super.dispose();
  }

  void _syncControllers() {
    _hourController.text = _hour.toString().padLeft(2, '0');
    _minuteController.text = _minute.toString().padLeft(2, '0');
  }

  void _parseInitialTime() {
    try {
      final parts = widget.initialTime24.split(':');
      final h24 = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      _isAm = h24 < 12;
      _hour = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24);
      _minute = m;
    } catch (_) {
      _hour = widget.isWakeTime ? 7 : 11;
      _minute = 0;
      _isAm = widget.isWakeTime;
    }
  }

  int get _hour24 => _isAm ? (_hour == 12 ? 0 : _hour) : (_hour == 12 ? 12 : _hour + 12);

  Color get _accentColor => _isAm ? const Color(0xFFF59E0B) : const Color(0xFF06B6D4);

  void _notifyTimeChanged() {
    final formatted = '${_hour24.toString().padLeft(2, '0')}:${_minute.toString().padLeft(2, '0')}';
    _syncControllers();
    widget.onTimeChanged(formatted);
  }

  void _toggleAmPm() {
    FlowHaptics.lightTap();
    setState(() {
      _isAm = !_isAm;
    });
    _notifyTimeChanged();
  }

  void _onManualHourTyped(String val) {
    if (val.isEmpty) return;
    int? parsed = int.tryParse(val);
    if (parsed != null) {
      if (parsed > 12) parsed = 12;
      if (parsed < 1 && val.length >= 2) parsed = 1;
      setState(() {
        _hour = parsed!;
      });
      _notifyTimeChanged();
      if (val.length >= 2 || (parsed > 1 && parsed <= 12)) {
        _minuteFocus.requestFocus();
      }
    }
  }

  void _onManualMinuteTyped(String val) {
    if (val.isEmpty) return;
    int? parsed = int.tryParse(val);
    if (parsed != null) {
      if (parsed > 59) parsed = 59;
      if (parsed < 0) parsed = 0;
      setState(() {
        _minute = parsed!;
      });
      _notifyTimeChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 8),

            // 1. Sleek Digital Time + Compact Small AM/PM Toggle
            _buildTimeRow(),

            const SizedBox(height: 24),

            // 2. The Hero: Circular Timer Clock Dial with Circle Loading Arc
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              child: _isTypingMode ? _buildManualTypingSection() : _buildCircularTimerDial(),
            ),

            const SizedBox(height: 14),

            // 3. Simple mode indicator hint
            Text(
              _selectingHours ? 'Select Hour on Clock' : 'Select Minute on Clock',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF94A3B8),
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 1. Digital Time Readout + Small Compact AM/PM Pill
  // ---------------------------------------------------------------------------
  Widget _buildTimeRow() {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Hour Box
        GestureDetector(
          onTap: () {
            FlowHaptics.selection();
            setState(() => _selectingHours = true);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: _selectingHours
                  ? _accentColor.withValues(alpha: 0.12)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _selectingHours ? _accentColor : const Color(0xFFE2E8F0),
                width: 1.8,
              ),
            ),
            child: Text(
              _hour.toString().padLeft(2, '0'),
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: _selectingHours ? _accentColor : const Color(0xFF0F172A),
              ),
            ),
          ),
        ),

        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            ':',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8)),
          ),
        ),

        // Minute Box
        GestureDetector(
          onTap: () {
            FlowHaptics.selection();
            setState(() => _selectingHours = false);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: !_selectingHours
                  ? _accentColor.withValues(alpha: 0.12)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: !_selectingHours ? _accentColor : const Color(0xFFE2E8F0),
                width: 1.8,
              ),
            ),
            child: Text(
              _minute.toString().padLeft(2, '0'),
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: !_selectingHours ? _accentColor : const Color(0xFF0F172A),
              ),
            ),
          ),
        ),

        const SizedBox(width: 12),

        // Small, Sleek AM / PM Toggle Button (No Overflow, Compact & Clean)
        GestureDetector(
          onTap: _toggleAmPm,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: _isAm ? const Color(0xFFFFFBEB) : const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _isAm ? const Color(0xFFFDE68A) : const Color(0xFF334155),
                width: 1.4,
              ),
              boxShadow: [
                BoxShadow(
                  color: _isAm
                      ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                      : Colors.black.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isAm ? Icons.wb_sunny_rounded : Icons.nightlight_round,
                  size: 16,
                  color: _isAm ? const Color(0xFFD97706) : const Color(0xFF38BDF8),
                ),
                const SizedBox(width: 5),
                Text(
                  _isAm ? 'AM' : 'PM',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: _isAm ? const Color(0xFFB45309) : Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(width: 6),

        // Keyboard Mode Toggle
        IconButton(
          icon: Icon(
            _isTypingMode ? Icons.access_time_rounded : Icons.keyboard_outlined,
            size: 20,
            color: _isTypingMode ? _accentColor : const Color(0xFF94A3B8),
          ),
          tooltip: _isTypingMode ? 'Use Clock' : 'Type Time',
          onPressed: () {
            FlowHaptics.lightTap();
            setState(() {
              _isTypingMode = !_isTypingMode;
              if (_isTypingMode) {
                _syncControllers();
                _hourFocus.requestFocus();
              }
            });
          },
        ),
      ],
    ),
    );
  }

  // ---------------------------------------------------------------------------
  // 2. Circular Timer Clock Dial with Circle Loading Arc
  // ---------------------------------------------------------------------------
  Widget _buildCircularTimerDial() {
    return Container(
      width: 236,
      height: 236,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: _accentColor.withValues(alpha: _isAm ? 0.08 : 0.22),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: _CircularTimerWidget(
        value: _selectingHours ? _hour : _minute,
        isHours: _selectingHours,
        isDay: _isAm,
        accentColor: _accentColor,
        onChanged: (val) {
          FlowHaptics.selection();
          setState(() {
            if (_selectingHours) {
              _hour = val;
            } else {
              _minute = val;
            }
          });
          _notifyTimeChanged();
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3. Compact Manual Typing View
  // ---------------------------------------------------------------------------
  Widget _buildManualTypingSection() {
    return Container(
      width: 240,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
      ),
      child: Column(
        children: [
          const Text(
            'Type time directly',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 58,
                child: TextField(
                  controller: _hourController,
                  focusNode: _hourFocus,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(2),
                  ],
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  decoration: InputDecoration(
                    labelText: 'Hour',
                    labelStyle: const TextStyle(fontSize: 11),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onChanged: _onManualHourTyped,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(':', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              ),
              SizedBox(
                width: 58,
                child: TextField(
                  controller: _minuteController,
                  focusNode: _minuteFocus,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(2),
                  ],
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  decoration: InputDecoration(
                    labelText: 'Min',
                    labelStyle: const TextStyle(fontSize: 11),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onChanged: _onManualMinuteTyped,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () {
              FlowHaptics.lightTap();
              setState(() => _isTypingMode = false);
            },
            child: Text(
              'Return to Clock Dial',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _accentColor),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Circular Timer Custom Widget & Painter with Circle Loading Arc
// =============================================================================
class _CircularTimerWidget extends StatelessWidget {
  final int value;
  final bool isHours;
  final bool isDay;
  final Color accentColor;
  final ValueChanged<int> onChanged;

  const _CircularTimerWidget({
    required this.value,
    required this.isHours,
    required this.isDay,
    required this.accentColor,
    required this.onChanged,
  });

  void _handlePan(Offset localPosition, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;
    double angle = math.atan2(dy, dx) + (math.pi / 2);
    if (angle < 0) angle += 2 * math.pi;

    if (isHours) {
      int hour = ((angle / (2 * math.pi)) * 12).round();
      if (hour == 0) hour = 12;
      onChanged(hour.clamp(1, 12));
    } else {
      int minute = ((angle / (2 * math.pi)) * 60).round();
      minute = (minute / 5).round() * 5;
      if (minute == 60) minute = 0;
      onChanged(minute.clamp(0, 55));
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          onPanDown: (details) => _handlePan(details.localPosition, size),
          onPanUpdate: (details) => _handlePan(details.localPosition, size),
          child: CustomPaint(
            size: size,
            painter: _CircularTimerPainter(
              value: value,
              isHours: isHours,
              isDay: isDay,
              accentColor: accentColor,
            ),
          ),
        );
      },
    );
  }
}

class _CircularTimerPainter extends CustomPainter {
  final int value;
  final bool isHours;
  final bool isDay;
  final Color accentColor;

  _CircularTimerPainter({
    required this.value,
    required this.isHours,
    required this.isDay,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 1. Dial Disc Background
    final bgPaint = Paint()
      ..color = isDay ? Colors.white : const Color(0xFF0F172A)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius - 2, bgPaint);

    // 2. Outer Circular Track Background (Dimmest Ring)
    final trackRadius = radius - 16;
    final trackPaint = Paint()
      ..color = isDay ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0;
    canvas.drawCircle(center, trackRadius, trackPaint);

    // 3. CIRCLE LOADING ARC: sweeps from 12 o'clock clockwise to the selected time
    final double sweepFraction;
    if (isHours) {
      sweepFraction = (value % 12 == 0 ? 12 : value % 12) / 12.0;
    } else {
      sweepFraction = value == 0 ? 0.01 : value / 60.0;
    }

    final sweepAngle = sweepFraction * (2 * math.pi);

    // Glowing Arc Glow (blur shadow behind the circle loading arc)
    final glowPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10.0
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: trackRadius),
      -math.pi / 2,
      sweepAngle,
      false,
      glowPaint,
    );

    // Active Circle Loading Arc (Crisp solid timer arc)
    final arcPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: trackRadius),
      -math.pi / 2,
      sweepAngle,
      false,
      arcPaint,
    );

    // 4. Center Pivot: Sun (Day) or Moon (Night)
    final pivotBg = Paint()
      ..color = isDay ? const Color(0xFFFEF3C7) : const Color(0xFF1E293B)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 14, pivotBg);

    final pivotBorder = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, 14, pivotBorder);

    // 5. Active Hand Angle and Node
    final double angle;
    if (isHours) {
      angle = (value % 12) * (2 * math.pi / 12) - (math.pi / 2);
    } else {
      angle = (value % 60) * (2 * math.pi / 60) - (math.pi / 2);
    }

    final handEnd = Offset(
      center.dx + trackRadius * math.cos(angle),
      center.dy + trackRadius * math.sin(angle),
    );

    // Slim Pointer line connecting center to arc node
    final handPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.5)
      ..strokeWidth = 1.8;
    canvas.drawLine(center, handEnd, handPaint);

    // Circular Timer Thumb Node on the Arc
    final nodeAura = Paint()
      ..color = accentColor.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(handEnd, 14, nodeAura);

    final nodePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(handEnd, 9, nodePaint);

    final nodeCenter = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(handEnd, 5, nodeCenter);

    // 6. Hour / Minute Numbers positioned cleanly inside the track
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    const count = 12;
    final numRadius = trackRadius - 26;

    for (int i = 1; i <= count; i++) {
      final numVal = isHours ? i : (i == 12 ? 0 : i * 5);
      final itemAngle = (i % 12) * (2 * math.pi / 12) - (math.pi / 2);
      final itemPos = Offset(
        center.dx + numRadius * math.cos(itemAngle),
        center.dy + numRadius * math.sin(itemAngle),
      );

      final isSelected = (value == numVal);
      final Color textColor = isSelected
          ? accentColor
          : (isDay ? const Color(0xFF64748B) : const Color(0xFF94A3B8));

      final textSpan = TextSpan(
        text: numVal.toString(),
        style: TextStyle(
          color: textColor,
          fontSize: isSelected ? 14 : 11.5,
          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
        ),
      );

      textPainter.text = textSpan;
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(itemPos.dx - textPainter.width / 2, itemPos.dy - textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CircularTimerPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.isHours != isHours ||
        oldDelegate.isDay != isDay ||
        oldDelegate.accentColor != accentColor;
  }
}
