import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// 将网络/异常信息转为用户可读的提示，供各页面统一使用。
String toUserFriendlyError(Object e) {
  final msg = e.toString();
  final code = msg.hashCode.abs().toRadixString(16).toUpperCase();
  debugPrint('[颐养年] 请求失败[$code] type=${e.runtimeType}');
  if (kDebugMode) debugPrint('[颐养年] 请求失败详情: $msg');
  if (e is PostgrestException) {
    if (['gateway_timeout', '504', '57014', 'PGRST003'].contains(e.code)) {
      return '服务响应超时，请稍后重试。';
    }
    if (['gateway_connection_failed', '502', '503', '521', '522', '523', '524'].contains(e.code)) {
      return '服务暂时不可用，请稍后重试。';
    }
  }
  if (e is http.ClientException || msg.contains('ClientException') ||
      msg.contains('HandshakeException') || msg.contains('Failed host lookup') ||
      msg.contains('No address associated with hostname') ||
      msg.contains('SocketException')) {
    return '暂时无法连接服务，请检查网络后重试。';
  }
  if (msg.contains('TimeoutException') || msg.contains('加载超时')) {
    return '加载超时，请检查网络后重试。';
  }
  return '操作未完成，请稍后重试（错误码：$code）';
}
