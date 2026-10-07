import 'dart:async';

import 'package:flowstate/services/timezone_service.dart';
import 'package:flowstate/theme/flow_motion.dart';

/// Applies to every test file (each runs in its own isolate).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // Repeating animations never settle; tests opt back in with FlowMotionScope(loopsEnabled: true).
  FlowMotion.debugLoopsEnabled = false;
  // The flutter_timezone platform channel never answers inside widget tests, which stalled every
  // timezone-aware request (Task 0, RC1). Files that test timezone handling set their own override.
  TimezoneService.overrideForTesting = () async => 'Asia/Kolkata';
  await testMain();
}
