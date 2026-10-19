/// 对可能因网络波动导致的 502/500、网络不可达、超时进行有限重试
Future<T> retryOnFailure<T>(
  Future<T> Function() fn, {
  int maxAttempts = 2,
  Duration delay = const Duration(milliseconds: 800),
}) async {
  Object? lastError;
  for (var i = 0; i < maxAttempts; i++) {
    try {
      return await fn();
    } catch (e) {
      lastError = e;
      final msg = e.toString();
      final isRetryable = msg.contains('502') ||
          msg.contains('500') ||
          msg.contains('Bad Gateway') ||
          msg.contains('Internal server error') ||
          msg.contains('Failed host lookup') ||
          msg.contains('No address associated with hostname') ||
          msg.contains('SocketException') ||
          msg.contains('TimeoutException') ||
          msg.contains('加载超时');
      if (isRetryable && i < maxAttempts - 1) {
        await Future.delayed(delay * (i + 1));
        continue;
      }
      rethrow;
    }
  }
  throw lastError ?? Exception('Retry failed');
}
