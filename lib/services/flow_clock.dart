import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Centralized Time & Clock Service for Flowstate.
///
/// Features:
/// - Provides device's local timezone-aware current time and date.
/// - Efficient minute-boundary timer that notifies listeners only on minute transitions,
///   preventing unnecessary second-by-second app-wide rebuilds.
/// - Observes Flutter AppLifecycleState: immediately refreshes on app resume.
class FlowClock extends ChangeNotifier with WidgetsBindingObserver {
  static final FlowClock _instance = FlowClock._internal();
  factory FlowClock() => _instance;

  static bool enableAutoTick = true;

  /// Tests: a fixed/advanceable clock instead of the device clock (null = the device clock).
  @visibleForTesting
  static DateTime Function()? debugNowOverride;

  /// The current time without creating the clock (and its minute timer): for code that only needs "now".
  static DateTime currentTime() => debugNowOverride?.call() ?? DateTime.now();

  Timer? _minuteTimer;
  DateTime _cachedNow = DateTime.now();

  FlowClock._internal() {
    _cachedNow = DateTime.now();
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {}
    if (enableAutoTick) {
      _scheduleNextMinuteTick();
    }
  }

  /// Current device local DateTime
  DateTime get now {
    final current = debugNowOverride?.call() ?? DateTime.now();
    _cachedNow = current;
    return current;
  }

  /// Latest cached minute timestamp
  DateTime get cachedNow => _cachedNow;

  /// Current local calendar date (midnight)
  DateTime get todayDate {
    final n = now;
    return DateTime(n.year, n.month, n.day);
  }

  /// Formatted date: "Tuesday, September 22"
  String get formattedDate => DateFormat('EEEE, MMMM d').format(now);

  /// Formatted short time: "8:22 PM"
  String get formattedTime => DateFormat('h:mm a').format(now);

  /// Current hour in local time (0..23)
  int get hour => now.hour;

  /// Current minute in local time (0..59)
  int get minute => now.minute;

  /// Time-of-day greeting
  String get timeOfDayGreeting {
    final h = now.hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  /// Calculates the fraction of the day that has elapsed (0.0 to 1.0)
  double get dayProgressFraction {
    final n = now;
    final totalMinutes = n.hour * 60 + n.minute;
    return (totalMinutes / 1440.0).clamp(0.0, 1.0);
  }

  /// Aligns the periodic timer to exact minute boundaries (:00 seconds)
  void _scheduleNextMinuteTick() {
    _minuteTimer?.cancel();
    final n = DateTime.now();
    final msUntilNextMinute = (60 - n.second) * 1000 - n.millisecond + 50;

    _minuteTimer = Timer(Duration(milliseconds: msUntilNextMinute), () {
      _cachedNow = DateTime.now();
      notifyListeners();
      // Once aligned to minute boundary, tick every 60 seconds
      _minuteTimer = Timer.periodic(const Duration(seconds: 60), (_) {
        _cachedNow = DateTime.now();
        notifyListeners();
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _cachedNow = DateTime.now();
      notifyListeners();
      _scheduleNextMinuteTick();
    }
  }

  /// Tests: deliver one minute tick to every listener (what the minute timer does in the app).
  @visibleForTesting
  void debugTick() {
    _cachedNow = now;
    notifyListeners();
  }

  /// Number of listeners currently attached (tests: no duplicate subscriptions).
  @visibleForTesting
  int get debugListenerCount => _debugListeners;
  int _debugListeners = 0;

  @override
  void addListener(VoidCallback listener) {
    _debugListeners++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _debugListeners = _debugListeners > 0 ? _debugListeners - 1 : 0;
    super.removeListener(listener);
  }

  /// Cancels any active timer (useful for testing)
  void stopTimer() {
    _minuteTimer?.cancel();
    _minuteTimer = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _minuteTimer?.cancel();
    super.dispose();
  }
}
