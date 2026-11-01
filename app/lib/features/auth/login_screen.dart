import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config.dart';
import '../../core/data_refresh.dart';
import '../../core/demo_credentials.dart';
import '../../core/error_message.dart';
import '../tree/tree_data_provider.dart';
import 'auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _connectionOk = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      _error = null;
      _connectionOk = false;
    });
    try {
      debugPrint('[颐养年] 测试服务连接...');
      await context.read<AuthService>().testConnection().timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('连接超时'),
      );
      if (mounted) {
        setState(() {
          _error = '网络连接正常，可以登录';
          _connectionOk = true;
        });
      }
      debugPrint('[颐养年] 连接测试成功');
    } catch (e) {
      debugPrint('[颐养年] 连接测试失败: $e');
      if (mounted) {
        setState(() {
          _error = '暂时无法连接服务，请检查网络后重试；如持续失败请联系管理员。';
          _connectionOk = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_loading || !_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    debugPrint('[颐养年] 开始登录...');
    try {
      await context.read<AuthService>().signIn(
        _emailController.text.trim(),
        _passwordController.text,
      );
      debugPrint('[颐养年] 登录成功');
      if (!mounted) return;
      context.read<DataRefreshNotifier>().notifyDataChanged();
      context.read<TreeDataProvider>().reset();
      unawaited(context.read<AuthService>().syncDevice());
      context.go('/home/inventory');
    } catch (e) {
      debugPrint('[颐养年] 登录失败: $e');
      if (mounted) {
        String msg = (e is AuthException ? e.message : e.toString())
            .replaceAll('Exception:', '')
            .replaceAll('AuthException:', '')
            .trim();
        if (msg.contains('Invalid login credentials')) {
          msg = '邮箱或密码错误';
        } else if (msg.contains('Email not confirmed')) {
          msg = '账号暂未启用，请联系管理员';
        } else if (e is TimeoutException) {
          msg = '登录超时，请检查网络后重试';
        } else if (msg.contains('SocketException') ||
            msg.contains('ClientException') ||
            msg.contains('Failed host lookup')) {
          msg = toUserFriendlyError(e);
        } else if (msg.contains('Rate limit')) {
          msg = '请求过于频繁，请稍后再试';
        }
        setState(() {
          _error = msg;
          _loading = false;
          _connectionOk = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _fillDemoCredentials() {
    _emailController.text = DemoCredentials.email;
    _passwordController.text = DemoCredentials.password;
    setState(() {
      _error = null;
      _connectionOk = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!Config.isBackendConfigured) {
      return Scaffold(
        appBar: AppBar(title: const Text('颐养年店铺管理')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 64,
                  color: Colors.orange,
                ),
                const SizedBox(height: 16),
                const Text(
                  '未配置数据服务',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  '请配置 SUPABASE_URL 和 SUPABASE_ANON_KEY 后重新运行。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '颐养年店铺管理',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '客户 · 储值 · 消费管理',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),
                  Card(
                    elevation: 0,
                    color: Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withValues(alpha: 0.35),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '体验账号',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '邮箱：${DemoCredentials.email}\n密码：${DemoCredentials.password}',
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(height: 1.4),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton(
                            onPressed: _loading ? null : _fillDemoCredentials,
                            child: const Text('一键填入体验账号'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    key: const Key('login_email'),
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: '邮箱',
                      hintText: '请输入登录邮箱',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.email],
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return '请输入邮箱';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('login_password'),
                    controller: _passwordController,
                    decoration: const InputDecoration(
                      labelText: '密码',
                      hintText: '请输入密码',
                      prefixIcon: Icon(Icons.lock_outlined),
                    ),
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    validator: (v) {
                      if (v == null || v.isEmpty) return '请输入密码';
                      return null;
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: _connectionOk ? Colors.green : Colors.red,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('登录'),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '登录遇到问题？可先检查网络连接',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _loading ? null : _testConnection,
                    child: const Text('检查网络'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
