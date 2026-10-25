import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/push_notification_service.dart';

class AuthService extends ChangeNotifier {
  AuthService([SupabaseClient? client]) : this.withOptions(client);

  AuthService.withOptions(
    this._client, {
    LocalStorage? sessionStorage,
    VoidCallback? onAccountChanged,
    Future<void> Function(SupabaseClient)? releaseDevice,
    this.enablePush = true,
  }) : _sessionStorage = sessionStorage,
       _onAccountChanged = onAccountChanged,
       _releaseDevice =
           releaseDevice ??
           ((client) =>
               PushNotificationService.releaseCurrentDevice(client: client)) {
    final client = _client;
    if (client != null) {
      _authSubscription = client.auth.onAuthStateChange.listen(
        _onAuthStateChange,
      );
    }
  }

  final SupabaseClient? _client;
  StreamSubscription<AuthState>? _authSubscription;
  User? _user;
  bool _initialized = false;
  bool _disposed = false;
  final bool enablePush;
  final LocalStorage? _sessionStorage;
  final VoidCallback? _onAccountChanged;
  final Future<void> Function(SupabaseClient) _releaseDevice;
  Future<void>? _logout;
  Completer<void>? _localLogout;

  void _setUser(User? user) {
    if (_disposed) return;
    final changed = _user?.id != user?.id;
    _user = user;
    if (changed) _onAccountChanged?.call();
    notifyListeners();
  }

  Future<void> testConnection() async {
    final client = _client;
    if (client == null) throw StateError('数据服务未配置');
    await client.from('customers').select('name').limit(1);
  }

  Future<void> syncDevice() async {
    if (!enablePush || _client == null) return;
    try {
      await PushNotificationService.syncCurrentDevice(client: _client);
    } catch (error) {
      debugPrint('Push sync skipped: ${error.runtimeType}');
    }
  }

  User? get user => _user;
  bool get isLoggedIn => _user != null;

  void _onAuthStateChange(AuthState data) {
    if (data.event == AuthChangeEvent.signedOut) {
      // An older SDK logout may finish local async cleanup after the next login.
      if (_client?.auth.currentSession != null) return;
      _setUser(null);
      if (!(_localLogout?.isCompleted ?? true)) _localLogout!.complete();
      return;
    }
    // 接受 SDK 恢复的 initialSession，以及后续登录、刷新令牌等状态。
    // 用户只有主动退出/切换账号或会话真正失效时才需要重新登录。
    _setUser(data.session?.user);
  }

  /// 后端客户端初始化后恢复本地会话；冷启动时直接复用有效会话。
  Future<void> ensureInitialized() async {
    final client = _client;
    if (_initialized || client == null) {
      _initialized = true;
      return;
    }
    _initialized = true;
    _setUser(client.auth.currentSession?.user);
  }

  Future<void> signIn(String email, String password) async {
    if (_logout != null) await _logout;
    final client = _client;
    if (client == null) {
      throw Exception('数据服务未配置');
    }
    await client.auth.signInWithPassword(email: email, password: password);
    // 与 onAuthStateChange 同步，避免登录成功后下一帧前 isLoggedIn 仍为 false，GoRouter 把用户打回登录页
    _setUser(client.auth.currentUser ?? client.auth.currentSession?.user);
  }

  Future<void> signOut() =>
      _logout ??= _signOutLocally().whenComplete(() => _logout = null);

  Future<void> _signOutLocally() async {
    final client = _client;
    if (client == null || client.auth.currentSession == null) {
      await _sessionStorage?.removePersistedSession();
      _setUser(null);
      return;
    }
    // Push cleanup uses the former JWT and cached device token, never blocks UI.
    if (enablePush) {
      unawaited(
        Future.sync(() => _releaseDevice(client)).catchError((Object e) {
          debugPrint('Push cleanup skipped: ${e.runtimeType}');
        }),
      );
    }
    _localLogout = Completer<void>();
    final remote = client.auth.signOut(scope: SignOutScope.local);
    unawaited(
      remote.catchError((Object error) {
        debugPrint('Remote logout incomplete: ${error.runtimeType}');
        if (!(_localLogout?.isCompleted ?? true)) {
          if (client.auth.currentSession == null) {
            _localLogout!.complete();
          } else {
            _localLogout!.completeError(error);
          }
        }
      }),
    );
    try {
      await _localLogout!.future.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      if (client.auth.currentSession != null) rethrow;
    } finally {
      _localLogout = null;
    }
    // Wait for the same initialized storage instance used by Supabase on startup.
    await _sessionStorage?.removePersistedSession();
    _setUser(null);
  }

  @override
  void dispose() {
    _disposed = true;
    _authSubscription?.cancel();
    super.dispose();
  }
}
