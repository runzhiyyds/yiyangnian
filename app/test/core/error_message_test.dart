import 'package:flutter_test/flutter_test.dart';
import 'package:yiyangnian/core/error_message.dart';

void main() {
  group('toUserFriendlyError', () {
    test('SocketException', () {
      final msg = toUserFriendlyError(Exception('SocketException: failed'));
      expect(msg, contains('无法连接服务器'));
    });

    test('Failed host lookup', () {
      final msg = toUserFriendlyError(Exception('Failed host lookup'));
      expect(msg, contains('无法连接服务器'));
    });

    test('TimeoutException', () {
      final msg = toUserFriendlyError(Exception('TimeoutException: ...'));
      expect(msg, contains('加载超时'));
    });

    test('unknown passes through', () {
      final e = Exception('Some error');
      expect(toUserFriendlyError(e), contains('Some error'));
    });
  });
}
