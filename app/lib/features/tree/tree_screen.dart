import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../customer/customer_model.dart';
import '../storage/storage_model.dart';
import '../consumption/consumption_model.dart';
import '../../core/data_refresh.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_placeholder.dart';
import 'tree_data_provider.dart';

class TreeScreen extends StatefulWidget {
  const TreeScreen({super.key});

  @override
  State<TreeScreen> createState() => _TreeScreenState();
}

class _TreeScreenState extends State<TreeScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  late final DataRefreshNotifier _refreshNotifier;

  @override
  void initState() {
    super.initState();
    _refreshNotifier = context.read<DataRefreshNotifier>();
    _refreshNotifier.addListener(_onDataChanged);
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureLoad());
  }

  /// [forceRefresh] 为 true 时忽略缓存重新请求（如下拉刷新、数据变更后）
  Future<void> _ensureLoad({bool forceRefresh = false}) async {
    if (!mounted) return;
    await context.read<TreeDataProvider>().load(context, forceRefresh: forceRefresh);
  }

  void _onDataChanged() {
    if (mounted) context.read<TreeDataProvider>().load(context, forceRefresh: true, invalidateReads: false);
  }

  @override
  void dispose() {
    _refreshNotifier.removeListener(_onDataChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final treeData = context.watch<TreeDataProvider>();
    if (treeData.loading && !treeData.hasLoaded) {
      return const Center(child: FullPageLoadingPlaceholder());
    }
    if (treeData.error != null && !treeData.hasLoaded) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                treeData.error!,
                style: TextStyle(color: Colors.red[800], height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => _ensureLoad(forceRefresh: true),
                child: const Text('重试'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context.push('/login'),
                icon: const Icon(Icons.login, size: 20),
                label: const Text('手动登录'),
              ),
            ],
          ),
        ),
      );
    }

    final filteredCustomers = _searchQuery.isEmpty
        ? treeData.customers
        : treeData.customers.where((c) => c.name.toLowerCase().contains(_searchQuery)).toList();

    final isEmpty = filteredCustomers.isEmpty;
    final isSearchEmpty = _searchQuery.isNotEmpty;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => _ensureLoad(forceRefresh: true),
        child: CustomScrollView(
          slivers: [
            if (treeData.loading) const SliverToBoxAdapter(child: LinearProgressIndicator()),
            if (treeData.error != null) SliverToBoxAdapter(child: MaterialBanner(
              content: Text('刷新失败，显示上次加载的客户信息。${treeData.error}'),
              actions: [TextButton(onPressed: () => _ensureLoad(forceRefresh: true), child: const Text('重试'))],
            )),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: '搜索客户姓名',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    isDense: true,
                  ),
                ),
              ),
            ),
            if (isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.people_outline,
                  title: isSearchEmpty ? '未找到匹配的客户' : '暂无客户',
                  subtitle: isSearchEmpty
                      ? '尝试修改搜索关键词'
                      : '点击右上角或下方按钮新建客户',
                  actionLabel: isSearchEmpty ? null : '新建客户',
                  onAction: isSearchEmpty ? null : () => context.push('/customer/new'),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final customer = filteredCustomers[index];
                    final storages = treeData.storagesByCustomer[customer.name] ?? [];
                    return _CustomerTreeTile(
                      customer: customer,
                      storages: storages,
                      consumptionsByStorage: treeData.consumptionsByStorage,
                      smallItemNames: treeData.smallItemNames,
                      onTap: () async {
                        await context.push('/customer/detail', extra: customer.name);
                        if (mounted) context.read<TreeDataProvider>().load(context);
                      },
                      onRefresh: () => context.read<TreeDataProvider>().load(context, forceRefresh: true),
                    );
                  },
                  childCount: filteredCustomers.length,
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ),
      ),
    );
  }
}

class _CustomerTreeTile extends StatelessWidget {
  final CustomerModel customer;
  final List<StorageRecordModel> storages;
  final Map<int, List<ConsumptionRecordModel>> consumptionsByStorage;
  final Map<int, String> smallItemNames;
  final Future<void> Function() onTap;
  final VoidCallback onRefresh;

  const _CustomerTreeTile({
    required this.customer,
    required this.storages,
    required this.consumptionsByStorage,
    required this.smallItemNames,
    required this.onTap,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final phoneStr = customer.phone != null && customer.phone!.isNotEmpty ? customer.phone! : '';
    final lifeStr = customer.lifeNumber != null ? '生命密码 ${customer.lifeNumber}' : '';
    final subtitle = [phoneStr, lifeStr].where((s) => s.isNotEmpty).join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.person_outline, size: 28),
            title: Text(
              customer.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: subtitle.isNotEmpty
                ? Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.grey[600]))
                : null,
            trailing: const Icon(Icons.chevron_right),
            onTap: () async => await onTap(),
          ),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              leading: const SizedBox(width: 28),
              title: Text(
                storages.isEmpty ? '暂无储值记录' : '查看储值记录（${storages.length}）',
                style: TextStyle(
                  fontSize: 13,
                  color: storages.isEmpty ? Colors.grey : null,
                ),
              ),
              enabled: storages.isNotEmpty,
              tilePadding: const EdgeInsets.symmetric(horizontal: 16),
              children: storages
                  .map((s) => _StorageTreeTile(
                        storage: s,
                        customerName: customer.name,
                        consumptions: consumptionsByStorage[s.id] ?? [],
                        smallItemNames: smallItemNames,
                        onRefresh: onRefresh,
                        onStorageTap: () async {
                          await context.push('/storage/${s.id}');
                          onRefresh();
                        },
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _StorageTreeTile extends StatelessWidget {
  final StorageRecordModel storage;
  final String customerName;
  final List<ConsumptionRecordModel> consumptions;
  final Map<int, String> smallItemNames;
  final VoidCallback onRefresh;
  final VoidCallback onStorageTap;

  const _StorageTreeTile({
    required this.storage,
    required this.customerName,
    required this.consumptions,
    required this.smallItemNames,
    required this.onRefresh,
    required this.onStorageTap,
  });

  @override
  Widget build(BuildContext context) {
    final smallItemStr = storage.storageSmallItemIds
        .map((id) => smallItemNames[id] ?? id.toString())
        .join('、');
    final title = smallItemStr.isNotEmpty
        ? '$customerName · $smallItemStr'
        : customerName;

    final consumptionCount = consumptions.length;
    return ExpansionTile(
      leading: const Icon(Icons.account_balance_wallet, size: 20),
      title: InkWell(
        onTap: onStorageTap,
        child: Text(
          '$title · ¥${storage.amount.toStringAsFixed(0)} · 消费 $consumptionCount 笔',
          style: const TextStyle(fontSize: 14),
        ),
      ),
      subtitle: (storage.storageBigItems.isNotEmpty || (storage.remark ?? '').isNotEmpty)
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (storage.storageBigItems.isNotEmpty)
                  Text(
                    storage.storageBigItems.join('、'),
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                if ((storage.remark ?? '').isNotEmpty)
                  Text(
                    storage.remark ?? '',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            )
          : null,
      children: consumptions.isEmpty
          ? [
              const ListTile(
                title: Text('暂无消费记录',
                    style: TextStyle(color: Colors.grey, fontSize: 13)),
              )
            ]
          : consumptions
              .map((c) {
                final ids = c.consumptionProjectIds.isNotEmpty
                    ? c.consumptionProjectIds
                    : (c.consumptionProjectId != null ? [c.consumptionProjectId!] : <int>[]);
                final names = ids
                    .map((id) => smallItemNames[id] ?? '')
                    .where((n) => n.isNotEmpty)
                    .toList();
                final projectsLabel = names.isNotEmpty ? names.join(' - ') : '';
                final dateStr = c.consumptionDate.toString().split(' ')[0];
                final display = projectsLabel.isNotEmpty
                    ? '$projectsLabel · $dateStr'
                    : dateStr;
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.receipt_long, size: 18),
                  title: Text(
                    display,
                    style: const TextStyle(fontSize: 13),
                  ),
                  subtitle: (c.remark ?? '').isNotEmpty
                      ? Text(
                          c.remark ?? '',
                          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : null,
                  onTap: () => context.push('/consumption/${c.id}/edit'),
                );
              })
              .toList(),
    );
  }
}
