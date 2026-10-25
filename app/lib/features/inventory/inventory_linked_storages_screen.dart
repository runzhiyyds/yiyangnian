import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/data_refresh.dart';
import '../../core/demo_mode.dart';
import '../../core/error_message.dart';
import '../../core/retry_helper.dart';
import '../../widgets/loading_placeholder.dart';
import '../auth/auth_service.dart';
import '../storage/storage_model.dart';
import '../storage/storage_repository.dart';
import '../storage_options/storage_small_item_repository.dart';
import 'widgets/inventory_linked_storages.dart';

class InventoryLinkedStoragesScreen extends StatefulWidget {
  const InventoryLinkedStoragesScreen({
    super.key,
    required this.smallItemId,
    this.initialSmallItemName,
  });

  final int smallItemId;
  final String? initialSmallItemName;

  @override
  State<InventoryLinkedStoragesScreen> createState() =>
      _InventoryLinkedStoragesScreenState();
}

class _InventoryLinkedStoragesScreenState
    extends State<InventoryLinkedStoragesScreen> {
  List<StorageRecordModel> _storages = const [];
  late String _smallItemName;
  bool _loading = true;
  String? _error;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  late final DataRefreshNotifier _refreshNotifier;

  @override
  void initState() {
    super.initState();
    _smallItemName = widget.initialSmallItemName?.trim().isNotEmpty == true
        ? widget.initialSmallItemName!.trim()
        : '当前小项';
    _refreshNotifier = context.read<DataRefreshNotifier>();
    _refreshNotifier.addListener(_onDataChanged);
    _searchController.addListener(() {
      if (!mounted) return;
      setState(
        () => _searchQuery = _searchController.text.trim().toLowerCase(),
      );
    });
    _load();
  }

  void _onDataChanged() {
    if (mounted) _load();
  }

  @override
  void dispose() {
    _refreshNotifier.removeListener(_onDataChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        retryOnFailure(() => context.read<StorageRepository>().getAll()),
        retryOnFailure(
          () => context.read<StorageSmallItemRepository>().getAll(),
        ),
      ]);
      if (!mounted) return;
      final email = context.read<AuthService>().user?.email;
      final storages =
          DemoMode.filterStorages(email, results[0] as List<StorageRecordModel>)
              .where(
                (storage) =>
                    storage.storageSmallItemIds.contains(widget.smallItemId),
              )
              .toList(growable: false);
      final options = DemoMode.filterSmallItemOptions(
        email,
        results[1] as List<StorageSmallItemOption>,
      );
      final matchingNames = options
          .where((option) => option.id == widget.smallItemId)
          .map((option) => option.name);
      setState(() {
        _storages = storages;
        if (matchingNames.isNotEmpty) _smallItemName = matchingNames.first;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = toUserFriendlyError(error);
      });
    }
  }

  Future<void> _openStorage(StorageRecordModel storage) async {
    await context.push('/storage/${storage.id}');
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final visibleStorages = _searchQuery.isEmpty
        ? _storages
        : _storages
              .where(
                (storage) =>
                    storage.customerName.toLowerCase().contains(_searchQuery) ||
                    storage.code.toLowerCase().contains(_searchQuery),
              )
              .toList(growable: false);
    return Scaffold(
      appBar: AppBar(title: const Text('关联储值')),
      body: _loading
          ? const Center(child: FullPageLoadingPlaceholder())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _load, child: const Text('重试')),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  Text(
                    _smallItemName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _searchQuery.isEmpty
                        ? '共 ${_storages.length} 条关联储值'
                        : '找到 ${visibleStorages.length} 条，共 ${_storages.length} 条',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: '搜索客户名或储值编号',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isEmpty
                          ? null
                          : IconButton(
                              tooltip: '清空搜索',
                              onPressed: _searchController.clear,
                              icon: const Icon(Icons.clear),
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  InventoryLinkedStorages(
                    storages: visibleStorages,
                    onTap: _openStorage,
                    showHeader: false,
                    emptyText: _searchQuery.isEmpty ? '暂无关联储值' : '没有匹配的关联储值',
                  ),
                ],
              ),
            ),
    );
  }
}
