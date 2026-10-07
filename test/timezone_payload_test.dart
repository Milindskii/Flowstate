import 'package:flowstate/services/ai_plan_service.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/timezone_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _CapturingApi extends ApiService {
  Map<String, dynamic>? lastBody;
  String? lastEndpoint;

  @override
  Future<dynamic> post(String endpoint, {dynamic body}) async {
    lastEndpoint = endpoint;
    lastBody = Map<String, dynamic>.from(body as Map);
    return {'tasks': [], 'ambiguities': [], 'needs_confirmation': false};
  }
}

void main() {
  tearDown(() {
    TimezoneService.overrideForTesting = null;
    TimezoneService.resetCache();
  });

  group('IANA timezone contract (finding 1)', () {
    test('isIana accepts real zones and rejects abbreviations', () {
      for (final ok in [
        'Asia/Kolkata',
        'America/Los_Angeles',
        'America/Argentina/Buenos_Aires',
        'UTC'
      ]) {
        expect(TimezoneService.isIana(ok), isTrue, reason: ok);
      }
      for (final bad in ['IST', 'India Standard Time', 'PST', '', 'garbage']) {
        expect(TimezoneService.isIana(bad), isFalse, reason: bad);
      }
      expect(TimezoneService.isIana(null), isFalse);
    });

    test('abbreviation from the OS is never reported as the device zone',
        () async {
      TimezoneService.overrideForTesting = () async => 'IST';
      expect(await TimezoneService.localIanaName(), isNull);
    });

    test(
        'generatePlan sends `timezone` (IANA) and the aware client clock, never user_timezone',
        () async {
      TimezoneService.overrideForTesting = () async => 'Asia/Kolkata';
      final api = _CapturingApi();
      await AIPlanService(api: api).generatePlan(rawText: 'gym at 6pm');
      expect(api.lastEndpoint, '/api/v1/ai/plan');
      expect(api.lastBody!['timezone'], 'Asia/Kolkata');
      expect(api.lastBody!.containsKey('user_timezone'), isFalse);
      expect(api.lastBody!.containsKey('current_date'), isFalse);
      final clock = api.lastBody!['current_local_time'] as String;
      expect(clock.endsWith('Z'), isTrue,
          reason: 'instants are sent as UTC with an explicit offset');
      expect(DateTime.parse(clock).isUtc, isTrue);
    });

    test(
        'when the zone is unknown the field is OMITTED so the server uses the stored preference',
        () async {
      TimezoneService.overrideForTesting = () async => null;
      final api = _CapturingApi();
      await AIPlanService(api: api).generatePlan(rawText: 'gym at 6pm');
      expect(api.lastBody!.containsKey('timezone'), isFalse);
    });
  });
}
