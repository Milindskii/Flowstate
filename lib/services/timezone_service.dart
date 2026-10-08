import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

/// Single source of the device's IANA timezone name (e.g. "Asia/Kolkata").
///
/// The backend contract (spec section 5) is one IANA name end to end. Abbreviations such as
/// "IST" (what `DateTime.now().timeZoneName` returns) are NOT valid and are never sent.
class TimezoneService {
  TimezoneService._();

  static final RegExp _iana =
      RegExp(r'^(UTC|[A-Za-z]+(?:/[A-Za-z0-9_+\-]+)+)$');
  static String? _cached;

  /// Test hook: force a value (or null to simulate "unavailable") instead of asking the OS.
  @visibleForTesting
  static Future<String?> Function()? overrideForTesting;

  @visibleForTesting
  static void resetCache() => _cached = null;

  /// True when [name] looks like an IANA zone key.
  static bool isIana(String? name) => name != null && _iana.hasMatch(name);

  /// Device IANA zone, or null when it cannot be determined. Callers must then OMIT the
  /// timezone field so the backend falls back to the user's stored preference.
  static Future<String?> localIanaName() async {
    final hook = overrideForTesting;
    if (hook != null) {
      final v = await hook();
      return isIana(v) ? v : null;
    }
    if (_cached != null) return _cached;
    try {
      // A platform channel that never answers must not hold a request (Replan, Build My Day) open forever.
      final info = await FlutterTimezone.getLocalTimezone().timeout(const Duration(seconds: 3));
      final id = info.identifier;
      if (isIana(id)) {
        _cached = id;
        return id;
      }
    } catch (_) {
      // unavailable on this platform; fall through
    }
    return null;
  }
}
