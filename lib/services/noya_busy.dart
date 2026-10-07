import 'dart:async';

import 'package:flutter/foundation.dart';

/// The one place that knows whether real async work is pending, so Noya can say so.
///
/// `track` raises the flag the moment the work starts (before any await) and lowers it in `finally`, so it
/// clears on success, failure and cancellation. A watchdog also releases a work item that outlives
/// [maxIndicatorTime]: the indicator never claims work that is not progressing; the work itself is never
/// cut short or faked.
class NoyaBusy extends ChangeNotifier {
  static const Duration defaultMaxIndicatorTime = Duration(seconds: 45);

  int _pending = 0;
  final List<String?> _labels = [];

  bool get isThinking => _pending > 0;

  /// What the most recent pending work is (e.g. "Rearranging your day"), if it said.
  String? get label => _labels.reversed.firstWhere((l) => l != null, orElse: () => null);

  int get pendingCount => _pending;

  Future<T> track<T>(
    Future<T> Function() work, {
    String? label,
    Duration maxIndicatorTime = defaultMaxIndicatorTime,
  }) async {
    var released = false;
    void release() {
      if (released) return;
      released = true;
      _pending--;
      _labels.remove(label);
      notifyListeners();
    }

    _pending++;
    _labels.add(label);
    notifyListeners();
    final watchdog = Timer(maxIndicatorTime, release);
    try {
      return await work();
    } finally {
      watchdog.cancel();
      release();
    }
  }
}
