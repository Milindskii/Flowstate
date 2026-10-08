import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowstate/utils/single_flight.dart';

void main() {
  test('rapid repeated calls run the action once and share its result', () async {
    final sf = SingleFlight();
    var runs = 0;
    final gate = Completer<int>();
    Future<int> action() {
      runs++;
      return gate.future;
    }

    final calls = [for (var i = 0; i < 5; i++) sf.run('claim-1', action)];
    expect(sf.isRunning('claim-1'), isTrue);
    gate.complete(42);
    expect(await Future.wait(calls), [42, 42, 42, 42, 42]);
    expect(runs, 1);
    expect(sf.isRunning('claim-1'), isFalse);
  });

  test('different keys run independently', () async {
    final sf = SingleFlight();
    var runs = 0;
    await Future.wait([
      sf.run('a', () async => runs++),
      sf.run('b', () async => runs++),
    ]);
    expect(runs, 2);
  });

  test('after it settles, the same key runs again (a new tap is a new request)', () async {
    final sf = SingleFlight();
    var runs = 0;
    await sf.run('k', () async => runs++);
    await sf.run('k', () async => runs++);
    expect(runs, 2);
  });

  test('a failure is shared, then released so a retry runs fresh', () async {
    final sf = SingleFlight();
    var runs = 0;
    final gate = Completer<void>();
    Future<void> failing() async {
      runs++;
      await gate.future;
      throw StateError('boom');
    }

    final first = sf.run('k', failing);
    final second = sf.run('k', failing);
    final results = [first, second].map((f) => f.then<Object?>((_) => null, onError: (Object e) => e)).toList();
    gate.complete();
    final errors = await Future.wait(results);
    expect(errors, everyElement(isA<StateError>()));
    expect(identical(first, second), isTrue);
    expect(runs, 1);
    expect(sf.isRunning('k'), isFalse);
    await sf.run('k', () async => runs++); // retry after the failure is a fresh request
    expect(runs, 2);
  });
}
