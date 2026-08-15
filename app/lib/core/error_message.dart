import 'package:flutter/foundation.dart';

/// 将网络/异常信息转为用户可读的提示，供各页面统一使用。
String toUserFriendlyError(Object e) {
  final msg = e.toString();
  debugPrint('[颐养年] 请求失败: $msg');
  if (msg.contains('Failed host lookup') ||
      msg.contains('No address associated with hostname') ||
      msg.contains('SocketException')) {
    return '暂时无法连接服务，请检查网络后重试。';
  }
  if (msg.contains('TimeoutException') || msg.contains('加载超时')) {
    return '加载超时，请检查网络后重试。';
  }
  final code = msg.hashCode.abs().toRadixString(16).toUpperCase();
  return '操作未完成，请稍后重试（错误码：$code）';
}
