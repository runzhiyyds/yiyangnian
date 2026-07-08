/// 将网络/异常信息转为用户可读的提示，供各页面统一使用。
String toUserFriendlyError(Object e) {
  final msg = e.toString();
  if (msg.contains('Failed host lookup') ||
      msg.contains('No address associated with hostname') ||
      msg.contains('SocketException')) {
    return '无法连接服务器，请检查网络。\n若当前网络无法访问外网，可尝试切换 WiFi/4G 或使用 VPN 后再点「重试」。';
  }
  if (msg.contains('TimeoutException') || msg.contains('加载超时')) {
    return '加载超时，请检查网络后重试。';
  }
  return msg;
}
