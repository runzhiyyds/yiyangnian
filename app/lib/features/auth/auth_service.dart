import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService extends ChangeNotifier {
  AuthService([this._client]) {
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

  User? get user => _user;
  bool get isLoggedIn => _user != null;

  void _onAuthStateChange(AuthState data) {
    if (data.event == AuthChangeEvent.signedOut) {
      _user = null;
      notifyListeners();
      return;
    }
    // 接受 SDK 恢复的 initialSession，以及后续登录、刷新令牌等状态。
    // 用户只有主动退出/切换账号或会话真正失效时才需要重新登录。
    _user = data.session?.user;
    notifyListeners();
  }

  /// Supabase.initialize 已完成本地会话恢复；冷启动时直接复用有效会话。
  Future<void> ensureInitialized() async {
    final client = _client;
    if (_initialized || client == null) {
      _initialized = true;
      return;
    }
    _user = client.auth.currentSession?.user;
    _initialized = true;
    notifyListeners();
  }

  Future<void> signIn(String email, String password) async {
    final client = _client;
    if (client == null) {
      throw Exception('Supabase 未配置');
    }
    await client.auth.signInWithPassword(email: email, password: password);
    // 与 onAuthStateChange 同步，避免登录成功后下一帧前 isLoggedIn 仍为 false，GoRouter 把用户打回登录页
    _user = client.auth.currentUser ?? client.auth.currentSession?.user;
    notifyListeners();
  }

  Future<void> signOut() async {
    final client = _client;
    if (client != null) {
      await client.auth.signOut();
    }
    _user = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
