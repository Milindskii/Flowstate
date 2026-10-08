import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/utils/friendly_error.dart';

/// Users never see raw technical failures: no stack traces, provider errors, HTTP statuses, JSON or exception names.
/// Failures read as calm, fixed sentences (the sleeping-Noya cards keep their own copy).
const _leaks = [
  'Exception',
  'SocketException',
  'ApiException',
  'XMLHttpRequest',
  'status',
  'statusCode',
  'Traceback',
  'gemini',
  'Gemini',
  'http',
  '500',
  '502',
  '{',
  '}',
  'null',
  'code:',
  'detail',
  'AuthRetryableFetchException',
  'AuthApiException',
  '_',
];

void expectCalm(String text, {String? reason}) {
  for (final leak in _leaks) {
    expect(text.contains(leak), isFalse, reason: '"$text" leaks "$leak" ${reason ?? ''}');
  }
  expect(text.trim(), isNotEmpty);
}

void main() {
  group('friendlyActionError', () {
    final cases = <String, Object>{
      'offline': const ApiException('Network connection failed: Connection refused'),
      'unexpected network': const ApiException('Unexpected network error: SocketException: Failed host lookup'),
      'timeout': const ApiException('timed out', isTimeout: true),
      'server 500 with a stack-like body': const ApiException('Request failed with status 500', statusCode: 500, data: {
        'detail': 'Internal error: model gemini_2 returned status 500 {code: x}',
      }),
      'bad gateway': const ApiException('Request failed with status 502', statusCode: 502),
      '422 with a validation list': const ApiException('x', statusCode: 422, data: {
        'detail': [
          {'loc': ['body', 'raw_text'], 'msg': 'String should have at most 1500 characters', 'type': 'string_too_long'}
        ],
      }),
      'unauthorised': const ApiException('x', statusCode: 401),
      'limit': const ApiException('x', statusCode: 429),
      'quota': const ApiException('x', statusCode: 402, data: {
        'detail': {'code': 'QUOTA_EXHAUSTED', 'shields_available': 0},
      }),
      'a plain exception': Exception('type \'Null\' is not a subtype of type \'String\' in type cast'),
      'a format error': const FormatException('Unexpected character (at character 1) <html>'),
      'a state error': StateError('Bad state: No element'),
    };

    cases.forEach((name, error) {
      test('$name reads as a calm sentence', () {
        expectCalm(friendlyActionError(error), reason: '($name)');
      });
    });

    test('a server message that already reads like a sentence is kept', () {
      const e = ApiException('x', statusCode: 400, data: {'detail': 'You need 20 more Flow Points for that.'});
      expect(friendlyActionError(e), 'You need 20 more Flow Points for that.');
    });

    test('a server message with internals is replaced, not shown', () {
      const e = ApiException('x', statusCode: 400, data: {'detail': 'IntegrityError: duplicate key value violates unique constraint "uq_x"'});
      expectCalm(friendlyActionError(e));
    });

    test('the caller\'s own fallback is used for unknown errors', () {
      expect(friendlyActionError(StateError('x'), fallback: 'That purchase did not go through.'), 'That purchase did not go through.');
    });

    test('offline errors say it is the connection', () {
      expect(friendlyActionError(const ApiException('Network connection failed: refused')), contains('connection'));
    });
  });

  group('friendlyAuthMessage', () {
    test('known provider messages become plain sentences', () {
      expect(friendlyAuthMessage(Exception('Invalid login credentials')), 'Invalid email or password. Please try again.');
      expect(friendlyAuthMessage(Exception('invalid_credentials')), 'Invalid email or password. Please try again.');
      expect(friendlyAuthMessage(Exception('User already registered')), 'Account already exists. Please log in instead.');
      expect(friendlyAuthMessage(Exception('Email not confirmed')),
          'Please check your email and verify your account before logging in.');
      expect(friendlyAuthMessage(Exception('over_email_send_rate_limit')),
          'Email rate limit reached. Please wait a few minutes before trying again.');
    });

    test('anything else never shows the raw provider text', () {
      final raw = Exception('AuthRetryableFetchException(message: {"code":502}, statusCode: 502)');
      expectCalm(friendlyAuthMessage(raw));
      expectCalm(friendlyAuthMessage(const ApiException('Network connection failed: refused')));
    });
  });

  test('plainOr keeps only text that reads like a sentence for people', () {
    expect(plainOr('Pick a time that has not passed.', 'Fallback.'), 'Pick a time that has not passed.');
    expect(plainOr('errors[0].message: field_required', 'Fallback.'), 'Fallback.');
    expect(plainOr('', 'Fallback.'), 'Fallback.');
  });

  group('source guard: no raw exception text is drawn on screen', () {
    // A screen may log an exception; it must not put it in a Text / SnackBar.
    final raw = <RegExp>[
      RegExp(r'Text\(\s*e\.(message|toString)'),
      RegExp(r'Text\(\s*err\b'),
      RegExp(r"Text\([^;]*\$\{?(e|err|error)\}?['" '"' r']'),
      RegExp(r'_errorMessage\s*=\s*e\.message'),
      RegExp(r'errorMessage\s*=\s*e\.toString'),
    ];

    test('screens and components pass errors through the friendly helpers', () {
      final offenders = <String>[];
      for (final dir in ['lib/screens', 'lib/components']) {
        for (final file in Directory(dir).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
          final lines = file.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            for (final pattern in raw) {
              if (pattern.hasMatch(lines[i])) offenders.add('${file.path}:${i + 1}: ${lines[i].trim()}');
            }
          }
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });
  });
}
