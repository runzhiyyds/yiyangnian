import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _tabTitles = ['库存管理', '客户信息一览', '店铺数据分析', '设置'];

  @override
  Widget build(BuildContext context) {
    final title =
        _tabTitles[navigationShell.currentIndex.clamp(
          0,
          _tabTitles.length - 1,
        )];
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (navigationShell.currentIndex == 1)
            IconButton(
              icon: const Icon(Icons.person_add),
              tooltip: '新建客户',
              onPressed: () => context.push('/customer/new'),
            ),
          if (navigationShell.currentIndex == 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('进货'),
                onPressed: () => context.push('/inventory/purchase/new'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: '库存管理',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: '客户信息一览',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics),
            label: '店铺数据分析',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
