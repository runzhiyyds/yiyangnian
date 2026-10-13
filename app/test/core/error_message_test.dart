import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yiyangnian/core/error_message.dart';

void main() {
  group('toUserFriendlyError', () {
    test('SocketException', () {
      final msg = toUserFriendlyError(Exception('SocketException: failed'));
      expect(msg, contains('暂时无法连接服务'));
    });

    test('Failed host lookup', () {
      final msg = toUserFriendlyError(Exception('Failed host lookup'));
      expect(msg, contains('暂时无法连接服务'));
    });

    test('TimeoutException', () {
      final msg = toUserFriendlyError(Exception('TimeoutException: ...'));
      expect(msg, contains('加载超时'));
    });

    test('connection closed without SocketException is a network error', () {
      expect(
        toUserFriendlyError(
          http.ClientException(
            'Connection closed before full header was received',
          ),
        ),
        contains('暂时无法连接服务'),
      );
    });
    test('gateway timeout is a readable timeout', () {
      const e = PostgrestException(
        message: 'upstream deadline',
        code: 'gateway_timeout',
      );
      expect(toUserFriendlyError(e), contains('服务响应超时'));
    });
    test('gateway unavailable is a readable service failure', () {
      const e = PostgrestException(
        message: 'upstream unavailable',
        code: 'gateway_connection_failed',
      );
      expect(toUserFriendlyError(e), contains('服务暂时不可用'));
    });
    test('database field misconfiguration has actionable diagnosis', () {
      expect(
        toUserFriendlyError(
          const PostgrestException(
            message: 'record "new" has no field "quantities"',
            code: '42703',
          ),
        ),
        contains('服务数据配置异常'),
      );
    });
    test('unknown returns a generic message and error code', () {
      final e = Exception('Some error');
      final msg = toUserFriendlyError(e);
      expect(msg, contains('操作未完成'));
      expect(msg, contains('错误码'));
      expect(msg, isNot(contains('Some error')));
    });
  });
}
