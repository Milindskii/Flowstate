import 'package:flutter/material.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_typography.dart';

/// Real 24-Hour Interactive Timeline Range Selector
///
/// Allows user to tap or drag along a 24-hour track to pick their peak energy hours.
/// Never displays static cards pretending to be an interactive control.
class FlowInteractiveTimeline extends StatefulWidget {
  final String initialWindowId; // e.g. 'morning', 'midday', 'afternoon', 'evening'
  final ValueChanged<String> onWindowChanged;

  const FlowInteractiveTimeline({
    super.key,
    required this.initialWindowId,
    required this.onWindowChanged,
  });

  @override
  State<FlowInteractiveTimeline> createState() => _FlowInteractiveTimelineState();
}

class _FlowInteractiveTimelineState extends State<FlowInteractiveTimeline> {
  late double _startHour; // 0.0 - 24.0
  late double _endHour;

  @override
  void initState() {
    super.initState();
    _initHoursFromWindow(widget.initialWindowId);
  }

  void _initHoursFromWindow(String id) {
    switch (id) {
      case 'morning':
        _startHour = 8.5;
        _endHour = 12.0;
        break;
      case 'midday':
        _startHour = 11.5;
        _endHour = 14.5;
        break;
      case 'afternoon':
        _startHour = 14.0;
        _endHour = 17.5;
        break;
      case 'evening':
        _startHour = 18.0;
        _endHour = 22.0;
        break;
      default:
        _startHour = 9.0;
        _endHour = 12.0;
    }
  }

  String _formatHour(double hour) {
    int h = hour.floor() % 24;
    int m = ((hour - hour.floor()) * 60).round();
    final suffix = h >= 12 ? 'PM' : 'AM';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$h12:${m.toString().padLeft(2, '0')} $suffix';
  }

  String _getWindowIdForHour(double mid) {
    if (mid >= 6 && mid < 11.5) return 'morning';
    if (mid >= 11.5 && mid < 14.0) return 'midday';
    if (mid >= 14.0 && mid < 18.0) return 'afternoon';
    return 'evening';
  }

  String _getWindowTitle(String id) {
    switch (id) {
      case 'morning':
        return 'Morning Clarity Window';
      case 'midday':
        return 'Midday Focus Window';
      case 'afternoon':
        return 'Afternoon Focus Window';
      case 'evening':
        return 'Evening Deep Work Window';
      default:
        return 'Personal Focus Window';
    }
  }

  void _handleTrackTapOrDrag(double localX, double trackWidth) {
    if (trackWidth <= 0) return;
    FlowHaptics.selection();
    final fraction = (localX / trackWidth).clamp(0.0, 1.0);
    final tappedHour = fraction * 24.0;
    const windowSpan = 3.5; // Typical 3.5 hour peak block

    setState(() {
      _startHour = (tappedHour - windowSpan / 2).clamp(0.0, 24.0 - windowSpan);
      _endHour = _startHour + windowSpan;
    });

    final mid = (_startHour + _endHour) / 2;
    final windowId = _getWindowIdForHour(mid);
    widget.onWindowChanged(windowId);
  }

  void _selectPreset(String windowId) {
    FlowHaptics.selection();
    setState(() {
      _initHoursFromWindow(windowId);
    });
    widget.onWindowChanged(windowId);
  }

  @override
  Widget build(BuildContext context) {
    final mid = (_startHour + _endHour) / 2;
    final currentId = _getWindowIdForHour(mid);
    final title = _getWindowTitle(currentId);
    final timeRange = '${_formatHour(_startHour)} – ${_formatHour(_endHour)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Readout Card
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: FlowColors.cyan.withValues(alpha: 0.4), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: FlowColors.cyan.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: FlowColors.cyan,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: FlowTypography.labelMedium(color: const Color(0xFF0F172A)).copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      timeRange,
                      style: FlowTypography.bodySmall(color: const Color(0xFF475569)),
                    ),
                  ],
                ),
              ),
              Text(
                '~3.5 hrs',
                style: FlowTypography.labelSmall(color: FlowColors.cyanDark).copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Interactive 24-Hour Scrubber Bar
        LayoutBuilder(
          builder: (context, constraints) {
            final trackWidth = constraints.maxWidth;
            final leftFraction = _startHour / 24.0;
            final widthFraction = (_endHour - _startHour) / 24.0;

            return GestureDetector(
              onTapDown: (details) => _handleTrackTapOrDrag(details.localPosition.dx, trackWidth),
              onPanUpdate: (details) => _handleTrackTapOrDrag(details.localPosition.dx, trackWidth),
              child: Container(
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
                ),
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    // Subtle background circadian gradient bands (Dawn, Day, Dusk, Night)
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(13),
                        child: Row(
                          children: [
                            // 00:00 - 06:00 (Night)
                            Expanded(
                              flex: 6,
                              child: Container(color: const Color(0xFF0F172A).withValues(alpha: 0.04)),
                            ),
                            // 06:00 - 12:00 (Morning)
                            Expanded(
                              flex: 6,
                              child: Container(color: const Color(0xFFF59E0B).withValues(alpha: 0.06)),
                            ),
                            // 12:00 - 18:00 (Afternoon)
                            Expanded(
                              flex: 6,
                              child: Container(color: const Color(0xFF38BDF8).withValues(alpha: 0.06)),
                            ),
                            // 18:00 - 24:00 (Evening)
                            Expanded(
                              flex: 6,
                              child: Container(color: const Color(0xFF6366F1).withValues(alpha: 0.05)),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Hour Tick Lines
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(9, (index) {
                            final h = index * 3;
                            return Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 1,
                                  height: index % 2 == 0 ? 14 : 8,
                                  color: const Color(0xFFCBD5E1),
                                ),
                                if (index % 2 == 0) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    h == 0 ? '12a' : (h == 12 ? '12p' : (h > 12 ? '${h - 12}p' : '${h}a')),
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: Color(0xFF94A3B8),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            );
                          }),
                        ),
                      ),
                    ),

                    // Draggable Active Highlight Window
                    Positioned(
                      left: leftFraction * trackWidth,
                      width: widthFraction * trackWidth,
                      top: 4,
                      bottom: 4,
                      child: Container(
                        decoration: BoxDecoration(
                          color: FlowColors.cyan.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: FlowColors.cyan, width: 2.0),
                          boxShadow: [
                            BoxShadow(
                              color: FlowColors.cyan.withValues(alpha: 0.18),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              width: 6,
                              margin: const EdgeInsets.only(left: 3),
                              decoration: BoxDecoration(
                                color: FlowColors.cyanDark,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const Icon(Icons.drag_indicator, size: 16, color: FlowColors.cyanDark),
                            Container(
                              width: 6,
                              margin: const EdgeInsets.only(right: 3),
                              decoration: BoxDecoration(
                                color: FlowColors.cyanDark,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 8),
        Center(
          child: Text(
            'Drag or tap along the timeline to position your peak window',
            style: FlowTypography.labelSmall(color: const Color(0xFF64748B)),
          ),
        ),

        const SizedBox(height: 16),

        // Quick Preset Chips
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            _buildPresetChip('Morning', 'morning', currentId == 'morning'),
            _buildPresetChip('Midday', 'midday', currentId == 'midday'),
            _buildPresetChip('Afternoon', 'afternoon', currentId == 'afternoon'),
            _buildPresetChip('Evening', 'evening', currentId == 'evening'),
          ],
        ),
      ],
    );
  }

  Widget _buildPresetChip(String label, String id, bool isSelected) {
    return ActionChip(
      label: Text(
        label,
        style: FlowTypography.labelSmall(
          color: isSelected ? Colors.white : const Color(0xFF334155),
        ).copyWith(fontWeight: FontWeight.w600),
      ),
      backgroundColor: isSelected ? const Color(0xFF0F172A) : Colors.white,
      side: BorderSide(
        color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
        width: 1.0,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onPressed: () => _selectPreset(id),
    );
  }
}
