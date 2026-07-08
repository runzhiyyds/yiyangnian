import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config.dart';

class AuthService extends ChangeNotifier {
  AuthService() {
    if (Config.isSupabaseConfigured) {
      _user = Supabase.instance.client.auth.currentUser;
      _authSubscription = Supabase.instance.client.auth.onAuthStateChange
          .listen((data) => _onAuthStateChange(data));
    }
  }

  StreamSubscription<AuthState>? _authSubscription;
  User? _user;

  User? get user => _user;
  bool get isLoggedIn => _user != null;

  void _onAuthStateChange(AuthState data) {
    _user = data.session?.user;
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
    _user = Supabase.instance.client.auth.currentUser ??
        Supabase.instance.client.auth.currentSession?.user;
    notifyListeners();
  }

  Future<void> signOut() async {
    if (Config.isSupabaseConfigured) {
      await Supabase.instance.client.auth.signOut();
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
