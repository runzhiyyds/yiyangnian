import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../auth/auth_service.dart';

/// 启动页只等待鉴权初始化；业务数据由用户进入页面后按需加载。
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _notConfigured = false;
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  void _goHome() {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;
    context.go('/home/inventory');
  }

  Future<void> _init() async {
    if (!Config.isSupabaseConfigured) {
      if (mounted) {
        setState(() => _notConfigured = true);
        _showNotConfigured();
      }
      return;
    }
    final auth = context.read<AuthService>();
    await auth.ensureInitialized();
    if (!mounted) return;
    if (!auth.isLoggedIn) {
      if (mounted) context.go('/login');
      return;
    }

    // 高频首页是库存，不再让客户树、完整分析或更新检查阻塞首屏。
    // 更新检查仍可从“设置”中主动执行。
    _goHome();
  }

  void _showNotConfigured() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('未配置'),
        content: const Text(
          '请在 app/env.json 中配置 SUPABASE_URL 和 SUPABASE_ANON_KEY，'
          '然后在 app 目录执行 ./scripts/generate_env_dart.sh，再重新运行应用。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF5F9F7), Color(0xFFE8F0ED)],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 80),
              Text(
                '颐养年店铺管理',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppTheme.primaryDark,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '顺顺送给妈妈的礼物，爱你哟',
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
              const Spacer(),
              if (_notConfigured)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    '未配置 Supabase\n请在 app/env.json 配置后执行 ./scripts/generate_env_dart.sh 再重新运行',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.red[700], fontSize: 14),
                  ),
                )
              else
                const CircularProgressIndicator(
                  color: AppTheme.primary,
                  strokeWidth: 2,
                ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}
