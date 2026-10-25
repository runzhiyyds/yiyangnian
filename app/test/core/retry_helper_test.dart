import 'package:flutter_test/flutter_test.dart';
import 'package:yiyangnian/core/retry_helper.dart';

void main() {
  group('retryOnFailure', () {
    test('succeeds on first call', () async {
      var calls = 0;
      final result = await retryOnFailure(() async {
        calls++;
        return 42;
      });
      expect(result, 42);
      expect(calls, 1);
    });

    test('retries on 502 then succeeds', () async {
      var calls = 0;
      final result = await retryOnFailure(() async {
        calls++;
        if (calls < 2) throw Exception('502 Bad Gateway');
        return 1;
      }, maxAttempts: 3, delay: Duration.zero);
      expect(result, 1);
      expect(calls, 2);
    });

    test('rethrows non-retryable', () async {
      var calls = 0;
      expect(
        () => retryOnFailure(() async {
          calls++;
          throw Exception('404 Not Found');
        }, maxAttempts: 3, delay: Duration.zero),
        throwsA(isA<Exception>()),
      );
      expect(calls, 1);
    });

    test('page-level transient retry is bounded to two attempts', () async {
      var calls = 0;
      await expectLater(
        retryOnFailure(() async {
          calls++;
          throw Exception('502');
        }, delay: const Duration(milliseconds: 1)),
        throwsException,
      );
      expect(calls, 2);
    });

    test('business errors are not retried', () async {
      var calls = 0;
      await expectLater(
        retryOnFailure(() async {
          calls++;
          throw Exception('invalid business input');
        }, delay: const Duration(milliseconds: 1)),
        throwsException,
      );
      expect(calls, 1);
    });
  });
}
