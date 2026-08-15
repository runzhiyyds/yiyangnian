import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../core/data_refresh.dart';
import '../../core/demo_mode.dart';
import '../../core/update_service.dart';
import '../auth/auth_service.dart';
import '../tree/tree_data_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _signOutAndGoLogin(BuildContext context, {required bool switchAccount}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(switchAccount ? '切换账号' : '退出登录'),
        content: Text(
          switchAccount
              ? '将退出当前账号，随后可使用其他账号登录。'
              : '确定退出当前账号吗？',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    context.read<DataRefreshNotifier>().notifyDataChanged();
    context.read<TreeDataProvider>().reset();
    await context.read<AuthService>().signOut();
    if (!context.mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final email = auth.user?.email;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          leading: const Icon(Icons.manage_accounts_outlined),
          title: const Text('账号管理'),
          subtitle: Text(
            email != null && email.isNotEmpty ? email : '未登录',
            style: TextStyle(color: Colors.grey[700]),
          ),
        ),
        if (DemoMode.isDemoUser(email))
          Card(
            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
            margin: const EdgeInsets.only(bottom: 8),
            child: const ListTile(
              leading: Icon(Icons.school_outlined),
              title: Text('体验模式'),
              subtitle: Text('当前仅展示「演示-」前缀的演示数据；正式账号不会看到演示数据'),
            ),
          ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('退出登录'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _signOutAndGoLogin(context, switchAccount: false),
        ),
        ListTile(
          leading: const Icon(Icons.swap_horiz),
          title: const Text('切换账号'),
          subtitle: const Text('退出后使用其他邮箱登录'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _signOutAndGoLogin(context, switchAccount: true),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.system_update),
          title: const Text('检查更新'),
          subtitle: Text(Config.hasPgyerCheck || Config.hasUpdateCheck
              ? '点击检查是否有新版本'
              : '当前未启用在线更新，请联系管理员'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _checkUpdate(context),
        ),
        const Divider(),
        FutureBuilder<String>(
          future: UpdateService.getCurrentVersion(),
          builder: (context, snap) {
            final v = snap.data ?? '-';
            return ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('当前版本'),
              trailing: Text('v$v', style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.w500)),
            );
          },
        ),
      ],
    );
  }

  Future<void> _checkUpdate(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!Config.hasPgyerCheck && !Config.hasUpdateCheck) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('当前未启用在线更新，请联系管理员'),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }
    messenger.showSnackBar(
      const SnackBar(content: Text('正在检查更新...')),
    );
    final current = await UpdateService.getCurrentVersion();
    final info = Config.hasPgyerCheck
        ? await UpdateService.checkUpdatePgyer()
        : await UpdateService.checkUpdate();
    if (!context.mounted) return;
    messenger.hideCurrentSnackBar();
    if (info == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('暂时无法检查更新，请确认网络后重试'),
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }
    if (!UpdateService.isNewerVersion(current, info.latestVersion)) {
      messenger.showSnackBar(
        SnackBar(content: Text('当前已是最新版本 v$current')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('发现新版本 v${info.latestVersion}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (info.releaseNote != null && info.releaseNote!.isNotEmpty)
              Text(info.releaseNote!),
            const SizedBox(height: 12),
            const Text('是否立即更新？'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('立即更新'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final apkUrl =
          info.apkUrl ?? info.androidUrl ?? info.downloadPageUrl;
      if (apkUrl == null || apkUrl.isEmpty) {
        // 兜底：若拿不到直链，仍然跳转到浏览器下载页
        await UpdateService.openDownload(info.downloadPageUrl);
        return;
      }
      final progressNotifier = ValueNotifier<DownloadProgress?>(null);
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
        messenger.showSnackBar(
          const SnackBar(
            content: Text('下载或安装更新失败，将打开下载页面'),
            duration: Duration(seconds: 4),
          ),
        );
        // 异常时退回原始逻辑：打开蒲公英下载页
        await UpdateService.openDownload(info.downloadPageUrl);
      } finally {
        if (Navigator.of(context, rootNavigator: true).canPop()) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        progressNotifier.dispose();
      }
    }
  }
}
