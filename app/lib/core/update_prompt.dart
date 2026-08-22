import 'dart:io';

import 'package:flutter/material.dart';

import 'config.dart';
import 'update_service.dart';

/// 首页自动提醒与设置页手动检查共用的更新流程。
class UpdatePrompt {
  UpdatePrompt._();

  static bool _showingDialog = false;

  static Future<void> checkAndPrompt(
    BuildContext context, {
    required bool manual,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!Config.hasPgyerCheck && !Config.hasUpdateCheck) {
      if (manual) {
        messenger.showSnackBar(
          const SnackBar(content: Text('当前未启用在线更新，请联系管理员')),
        );
      }
      return;
    }
    if (_showingDialog) return;

    if (manual) {
      messenger.showSnackBar(const SnackBar(content: Text('正在检查更新...')));
    }
    final current = await UpdateService.getCurrentVersion();
    final info = Config.hasPgyerCheck
        ? await UpdateService.checkUpdatePgyer()
        : await UpdateService.checkUpdate();
    if (!context.mounted) return;
    if (manual) messenger.hideCurrentSnackBar();

    if (info == null) {
      if (manual) {
        messenger.showSnackBar(
          const SnackBar(content: Text('暂时无法检查更新，请确认网络后重试')),
        );
      }
      return;
    }
    if (!UpdateService.isNewerVersion(current, info.latestVersion)) {
      if (manual) {
        messenger.showSnackBar(SnackBar(content: Text('当前已是最新版本 v$current')));
      }
      return;
    }
    final isDownloading = await UpdateService.isBackgroundDownloadActive();
    if (!context.mounted) return;
    if (isDownloading) {
      if (manual) {
        messenger.showSnackBar(
          const SnackBar(content: Text('新版本正在后台下载，请查看通知栏进度')),
        );
      }
      return;
    }

    _showingDialog = true;
    final shouldUpdate = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('发现新版本 v${info.latestVersion}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (info.releaseNote != null && info.releaseNote!.trim().isNotEmpty)
              Text(info.releaseNote!.trim()),
            const SizedBox(height: 12),
            const Text('可在应用内后台下载，通知栏会显示进度。下载完成后可直接安装。'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('稍后'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.download_outlined),
            label: const Text('后台下载'),
          ),
        ],
      ),
    );
    _showingDialog = false;
    if (shouldUpdate != true || !context.mounted) return;

    final apkUrl = info.apkUrl ?? info.androidUrl;
    final fallbackUrl = info.downloadPageUrl ?? info.androidUrl;
    if (!Platform.isAndroid || apkUrl == null || apkUrl.isEmpty) {
      await UpdateService.openDownload(fallbackUrl);
      return;
    }

    try {
      await UpdateService.startBackgroundDownload(
        apkUrl: apkUrl,
        version: info.latestVersion,
        fallbackUrl: fallbackUrl,
      );
      if (!context.mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('已开始后台下载，可在 Android 通知栏查看进度'),
          duration: Duration(seconds: 5),
        ),
      );
    } catch (_) {
      if (context.mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('应用内下载启动失败，将打开蒲公英下载页')),
        );
      }
      await UpdateService.openDownload(fallbackUrl);
    }
  }
}
