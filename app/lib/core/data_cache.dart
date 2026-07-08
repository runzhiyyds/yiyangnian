/// 全局内存缓存：已加载过的数据在本地保存，减少重复请求。
/// 支持按前缀失效 [removeByPrefix]、可选容量上限 [maxSize]、可选 TTL 过期。
/// 在 [DataRefreshNotifier] 中可按模块失效或全量清空。
class DataCache {
  DataCache({this.maxSize});

  final Map<String, Object?> _store = {};
  final List<String> _keyOrder = [];
  final Map<String, DateTime> _expiry = {};

  /// 最大缓存条目数，null 表示不限制。超过时淘汰最早写入的 key。
  final int? maxSize;

  T? get<T>(String key) {
    final exp = _expiry[key];
    if (exp != null && DateTime.now().isAfter(exp)) {
      remove(key);
      return null;
    }
    final v = _store[key];
    return v is T ? v : null;
  }

  void set<T>(String key, T value, {Duration? ttl}) {
    if (ttl != null) {
      _expiry[key] = DateTime.now().add(ttl);
    } else {
      _expiry.remove(key);
    }
    if (_store.containsKey(key)) {
      _store[key] = value;
      return;
    }
    if (maxSize != null && _keyOrder.length >= maxSize!) {
      while (_keyOrder.isNotEmpty && _keyOrder.length >= maxSize!) {
        final oldest = _keyOrder.removeAt(0);
        _store.remove(oldest);
        _expiry.remove(oldest);
      }
    }
    _keyOrder.add(key);
    _store[key] = value;
  }

  void remove(String key) {
    _store.remove(key);
    _keyOrder.remove(key);
    _expiry.remove(key);
  }

  /// 移除所有以 [prefix] 开头的 key，用于按模块失效。
  void removeByPrefix(String prefix) {
    final toRemove = _store.keys.where((k) => k.startsWith(prefix)).toList();
    for (final k in toRemove) {
      _store.remove(k);
      _keyOrder.remove(k);
      _expiry.remove(k);
    }
  }

  void clear() {
    _store.clear();
    _keyOrder.clear();
    _expiry.clear();
  }
}
