import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/today_service.dart';

class _FailingApi extends ApiService {
  int gets = 0;
  @override
  Future<dynamic> get(String endpoint, {Map<String, String>? queryParams, Map<String, String>? headers}) async {
    gets++;
    throw const ApiException('offline', statusCode: 503);
  }
}

void main() {
  test('after a write, a failed Today fetch throws instead of silently serving the last cached snapshot', () async {
    // An old snapshot is on disk (what the pre-write schedule looked like).
    SharedPreferences.setMockInitialValues({'flowstate_today_cache': '{"stale":true}'});
    final api = _FailingApi();
    final service = TodayService(api: api);

    await expectLater(service.getTodayExperience(allowCachedFallback: false), throwsA(isA<ApiException>()));
    expect(api.gets, 1);
  });
}
