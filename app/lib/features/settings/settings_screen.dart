import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../core/data_refresh.dart';
import '../../core/demo_mode.dart';
import '../../core/update_prompt.dart';
import '../../core/update_service.dart';
import '../auth/auth_service.dart';
import '../tree/tree_data_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _signOutAndGoLogin(
    BuildContext context, {
    required bool switchAccount,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(switchAccount ? '切换账号' : '退出登录'),
        content: Text(switchAccount ? '将退出当前账号，随后可使用其他账号登录。' : '确定退出当前账号吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确定'),
          ),
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
            color: Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: 0.35),
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
          subtitle: Text(
            Config.hasPgyerCheck || Config.hasUpdateCheck
                ? '点击检查是否有新版本'
                : '当前未启用在线更新，请联系管理员',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => UpdatePrompt.checkAndPrompt(context, manual: true),
        ),
        const Divider(),
        FutureBuilder<String>(
          future: UpdateService.getCurrentVersion(),
          builder: (context, snapshot) {
            final version = snapshot.data ?? '-';
            return ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('当前版本'),
              trailing: Text(
                'v$version',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
