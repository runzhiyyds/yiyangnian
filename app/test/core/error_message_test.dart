import 'package:flutter_test/flutter_test.dart';
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

    test('unknown returns a generic message and error code', () {
      final e = Exception('Some error');
      final msg = toUserFriendlyError(e);
      expect(msg, contains('操作未完成'));
      expect(msg, contains('错误码'));
      expect(msg, isNot(contains('Some error')));
    });
  });
}
