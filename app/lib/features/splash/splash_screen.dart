import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../core/update_service.dart';
import '../analytics/store_analytics_screen.dart';
import '../auth/auth_service.dart';
import '../tree/tree_data_provider.dart';

/// 启动页：等待鉴权初始化；已在本进程内登录则预加载首页数据，否则进入登录页
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _notConfigured = false;
  bool _hasNavigated = false;
  Timer? _safetyTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _safetyTimer?.cancel();
    super.dispose();
  }

  void _goHome() {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;
    _safetyTimer?.cancel();
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
      _safetyTimer?.cancel();
      if (mounted) context.go('/login');
      return;
    }

    // Release 下有时 timeout 不触发，导致一直停在启动页。用定时器兜底：先进入首页，数据由 TreeScreen 继续加载
    _safetyTimer = Timer(const Duration(seconds: 12), () {
      if (mounted) _goHome();
    });
    if (!mounted) return;
    // 已登录时在启动页并行预加载首页与店铺分析数据，避免进入分析页时二次等待
    if (auth.isLoggedIn) {
      try {
        final treeData = context.read<TreeDataProvider>();
        // 预加载不宜过久阻塞启动页；树数据已改为少量请求，多数情况几秒内完成
        await Future.wait([
          treeData
              .load(context)
              .timeout(
                const Duration(seconds: 18),
                onTimeout: () => throw TimeoutException('预加载超时'),
              ),
          preloadStoreAnalyticsData(context).timeout(
            const Duration(seconds: 18),
            onTimeout: () => throw TimeoutException('分析预加载超时'),
          ),
        ]);
      } catch (e) {
        debugPrint('splash: preload failed (tree or analytics): $e');
      }
    }
    if (!mounted) return;
    await _maybeShowUpdateDialog();
    if (!mounted) return;
    _goHome();
  }

  Future<void> _maybeShowUpdateDialog() async {
    if (!mounted) return;
    UpdateInfo? info;
    if (Config.hasPgyerCheck) {
      info = await UpdateService.checkUpdatePgyer();
    } else if (Config.hasUpdateCheck) {
      info = await UpdateService.checkUpdate();
    }
    if (!mounted || info == null) return;
    final current = await UpdateService.getCurrentVersion();
    if (!UpdateService.isNewerVersion(current, info.latestVersion)) return;
    if (!mounted) return;
    // 有更新时取消安全定时器，避免在用户未操作或下载/安装过程中被强制进入首页
    _safetyTimer?.cancel();
    _safetyTimer = null;
    final updateInfo = info;
    final open = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('发现新版本 v${updateInfo.latestVersion}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (updateInfo.releaseNote != null &&
                  updateInfo.releaseNote!.isNotEmpty)
                Text(updateInfo.releaseNote!),
              const SizedBox(height: 12),
              const Text('是否立即更新？'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('立即更新'),
          ),
        ],
      ),
    );
    if (open == true && mounted) {
      final apkUrl =
          updateInfo.apkUrl ??
          updateInfo.androidUrl ??
          updateInfo.downloadPageUrl;
      if (apkUrl == null || apkUrl.isEmpty) {
        // 兜底：若拿不到直链，仍然跳转到浏览器下载页
        await UpdateService.openDownload(updateInfo.downloadPageUrl);
        return;
      }
      final progressNotifier = ValueNotifier<DownloadProgress?>(null);
      // 显示下载进度对话框
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('正在下载更新'),
          content: ValueListenableBuilder<DownloadProgress?>(
            valueListenable: progressNotifier,
            builder: (ctx, progress, _) {
              final p = progress?.progress ?? 0;
              final percent = (p * 100).clamp(0, 100).toStringAsFixed(0);
              String sizeText = '';
              if (progress != null && progress.total > 0) {
                final receivedMb = (progress.received / 1024 / 1024);
                final totalMb = (progress.total / 1024 / 1024);
                sizeText =
                    '（${receivedMb.toStringAsFixed(1)} / ${totalMb.toStringAsFixed(1)} MB）';
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: progress?.total == null || progress!.total <= 0
                        ? null
                        : p,
                  ),
                  const SizedBox(height: 12),
                  Text('已完成 $percent%$sizeText'),
                  const SizedBox(height: 4),
                  const Text(
                    '请保持应用在前台，下载完成后将自动弹出安装界面。',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              );
            },
          ),
        ),
      );
      try {
        final file = await UpdateService.downloadApk(
          apkUrl,
          onProgress: (p) => progressNotifier.value = p,
        );
        await UpdateService.installApk(file.path);
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('下载或安装更新失败，将打开下载页面'),
            duration: Duration(seconds: 4),
          ),
        );
        // 异常时退回原始逻辑：打开蒲公英下载页
        await UpdateService.openDownload(updateInfo.downloadPageUrl);
      } finally {
        if (Navigator.of(context, rootNavigator: true).canPop()) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        progressNotifier.dispose();
      }
    }
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
