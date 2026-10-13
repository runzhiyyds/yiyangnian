import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

const gatewayHost = 'yiyangnian-api.pet-food-advisor.asia';
const originalSessionKey = 'sb-jhntjagskjklbrsgturh-auth-token';

/// This gateway is fixed to the original project; retain its existing session.
/// Other hosts keep the SDK default instead of inheriting another project's key.
FlutterAuthClientOptions supabaseAuthOptions(String url) =>
    FlutterAuthClientOptions(
      localStorage: Uri.parse(url).host == gatewayHost
          ? QueuedSessionStorage(
              SharedPreferencesLocalStorage(
                persistSessionKey: originalSessionKey,
              ),
            )
          : null,
    );

/// SDK auth events persist asynchronously. Queue them with the explicit local
/// logout so a delayed removal cannot erase the next account's saved session.
class QueuedSessionStorage extends LocalStorage {
  QueuedSessionStorage(this.inner);
  final LocalStorage inner;
  Future<void> _tail = Future.value();

  Future<T> _enqueue<T>(Future<T> Function() work) {
    final next = _tail.catchError((Object _) {}).then((_) => work());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  @override
  Future<void> initialize() => inner.initialize();
  @override
  Future<bool> hasAccessToken() => _enqueue(inner.hasAccessToken);
  @override
  Future<String?> accessToken() => _enqueue(inner.accessToken);
  @override
  Future<void> removePersistedSession() =>
      _enqueue(inner.removePersistedSession);
  @override
  Future<void> persistSession(String session) =>
      _enqueue(() => inner.persistSession(session));
}
