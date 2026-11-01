import 'dart:async';

/// Short-lived, account-scoped read sharing. Never caches auth or writes.
/// Invalidation also detaches pending reads so old responses cannot repopulate.
class RepositoryReadCache {
  RepositoryReadCache(
    this.accountId, {
    this.ttl = const Duration(seconds: 30),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final String? Function() accountId;
  final Duration ttl;
  final DateTime Function() _clock;
  final Map<String, ({Object value, DateTime expires})> _values = {};
  final Map<String, Future<Object>> _pending = {};
  int _revision = 0;

  Future<List<T>> read<T>(String query, Future<List<T>> Function() load) async {
    final owner = accountId();
    if (owner == null) return load();
    final key = '$owner:$query';
    final value = _values[key];
    if (value != null && _clock().isBefore(value.expires)) {
      return List<T>.from(value.value as List<T>);
    }
    final revision = _revision;
    final pending = _pending[key];
    if (pending != null) return List<T>.from(await pending as List<T>);
    final future = Future<List<T>>.sync(load);
    _pending[key] = future;
    try {
      final rows = await future;
      if (_revision == revision && accountId() == owner) {
        if (_values.length >= 80) _values.remove(_values.keys.first);
        _values[key] = (
          value: List<T>.unmodifiable(rows),
          expires: _clock().add(ttl),
        );
      }
      return List<T>.from(rows);
    } finally {
      if (identical(_pending[key], future)) _pending.remove(key);
    }
  }

  void clear() {
    _revision++;
    _values.clear();
    _pending.clear();
  }
}
