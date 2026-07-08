import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config.dart';

class AuthService extends ChangeNotifier {
  AuthService() {
    if (Config.isSupabaseConfigured) {
      _authSubscription = Supabase.instance.client.auth.onAuthStateChange
          .listen((data) => _onAuthStateChange(data));
    }
  }

  StreamSubscription<AuthState>? _authSubscription;
  User? _user;
  bool _sessionVerified = false;
  bool _initialized = false;

  User? get user => _user;
  /// 仅在本进程内用户显式登录成功后为 true；忽略 Supabase 本地恢复的会话。
  bool get isLoggedIn => _sessionVerified && _user != null;

  void _onAuthStateChange(AuthState data) {
    if (data.event == AuthChangeEvent.signedOut) {
      _user = null;
      _sessionVerified = false;
      notifyListeners();
      return;
    }
    if (!_sessionVerified) return;
    _user = data.session?.user;
    notifyListeners();
  }

  /// 等待 Supabase 完成本地会话恢复，并清除未在本进程内验证的持久化会话。
  Future<void> ensureInitialized() async {
    if (_initialized || !Config.isSupabaseConfigured) {
      _initialized = true;
      return;
    }
    try {
      await Supabase.instance.client.auth.onAuthStateChange
          .timeout(const Duration(seconds: 5))
          .firstWhere((data) => data.event == AuthChangeEvent.initialSession);
    } catch (_) {
      // 超时后仍按当前 auth 状态继续，避免启动页卡死
    }
    if (!_sessionVerified &&
        Supabase.instance.client.auth.currentSession != null) {
      await Supabase.instance.client.auth.signOut();
      _user = null;
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> signIn(String email, String password) async {
    if (!Config.isSupabaseConfigured) {
      throw Exception('Supabase 未配置');
    }
    await Supabase.instance.client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    // 与 onAuthStateChange 同步，避免登录成功后下一帧前 isLoggedIn 仍为 false，GoRouter 把用户打回登录页
    _sessionVerified = true;
    _user = Supabase.instance.client.auth.currentUser ??
        Supabase.instance.client.auth.currentSession?.user;
    notifyListeners();
  }

  Future<void> signOut() async {
    if (Config.isSupabaseConfigured) {
      await Supabase.instance.client.auth.signOut();
    }
    _user = null;
    _sessionVerified = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
