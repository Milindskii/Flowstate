import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state_provider.dart';
import '../services/noya_busy.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_typography.dart';
import 'noya_companion_view.dart';
import 'noya_motion_view.dart';

/// Noya, thinking while [active] is true and resting otherwise. The single reusable "work in progress" avatar:
/// screens pass their own real pending flag, nothing here decides that work is happening.
/// Reduced motion is handled by [NoyaMotionView] (the thinking pose is shown still).
class NoyaThinking extends StatelessWidget {
  final bool active;
  final double size;

  const NoyaThinking({super.key, required this.active, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return NoyaMotionView(
      key: Key(active ? 'noya_thinking_on' : 'noya_thinking_off'),
      mood: active ? NoyaMood.thinking : NoyaMood.rest,
      pose: active ? NoyaState.thinking : NoyaState.idle,
      size: size,
      semanticLabel: active ? 'Noya is working on it' : null,
    );
  }
}

/// App-wide chip shown while any tracked async work is pending (see `NoyaBusy`). It appears the moment the
/// work starts and disappears when it ends; it renders nothing when nothing is pending.
class NoyaBusyBadge extends StatelessWidget {
  const NoyaBusyBadge({super.key});

  @override
  Widget build(BuildContext context) {
    // select: the badge rebuilds only when the busy tracker itself changes, not on every provider notify
    final busy = context.select<AppStateProvider, NoyaBusy>((s) => s.busy);
    return ListenableBuilder(
      listenable: busy,
      builder: (context, _) {
        if (!busy.isThinking) return const SizedBox.shrink(key: Key('noya_busy_idle'));
        return Semantics(
          liveRegion: true,
          label: busy.label ?? 'Working on it',
          child: Container(
            key: const Key('noya_busy_badge'),
            padding: const EdgeInsets.fromLTRB(8, 4, 14, 4),
            decoration: BoxDecoration(
              color: FlowColors.surfaceElevated(context),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: FlowColors.border(context)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const NoyaThinking(active: true, size: 32),
                const SizedBox(width: 6),
                Text(
                  busy.label ?? 'Working on it',
                  style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
