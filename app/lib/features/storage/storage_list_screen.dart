import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/data_cache.dart';
import '../../core/demo_mode.dart';
import '../../widgets/loading_placeholder.dart';
import '../../core/data_refresh.dart';
import '../../core/error_message.dart';
import '../../core/retry_helper.dart';
import '../auth/auth_service.dart';
import '../storage_options/storage_small_item_repository.dart';
import 'storage_model.dart';
import 'storage_repository.dart';

class _StorageListCache {
  _StorageListCache({
    required this.storages,
    required this.remainingByStorage,
    required this.smallItemNames,
  });
  final List<StorageRecordModel> storages;
  final Map<int, int> remainingByStorage;
  final Map<int, String> smallItemNames;
}

class StorageListScreen extends StatefulWidget {
  const StorageListScreen({super.key});

  @override
  State<StorageListScreen> createState() => _StorageListScreenState();
}

class _StorageListScreenState extends State<StorageListScreen> {
  List<StorageRecordModel> _storages = [];
  Map<int, int> _remainingByStorage = {};
  Map<int, String> _smallItemNames = {};
  bool _loading = true;
  String? _error;
  bool _loadInProgress = false;
  late final DataRefreshNotifier _refreshNotifier;

  @override
  void initState() {
    super.initState();
    _refreshNotifier = context.read<DataRefreshNotifier>();
    _refreshNotifier.addListener(_onDataChanged);
    _load();
  }

  void _onDataChanged() {
    if (mounted) _load();
  }

  @override
  void dispose() {
    _refreshNotifier.removeListener(_onDataChanged);
    super.dispose();
  }

  static const _cacheKeyPrefix = 'storage_list';

  String _listCacheKey(BuildContext context) {
    final email = context.read<AuthService>().user?.email;
    return '${_cacheKeyPrefix}_${DemoMode.cacheSuffix(email)}';
  }

  Future<void> _load() async {
    if (!mounted) return;
    final cache = context.read<DataCache>();
    final cacheKey = _listCacheKey(context);
    final cached = cache.get<_StorageListCache>(cacheKey);
    if (cached != null) {
      setState(() {
        _storages = cached.storages;
        _remainingByStorage = cached.remainingByStorage;
        _smallItemNames = cached.smallItemNames;
        _loading = false;
        _error = null;
      });
      return;
    }
    if (_loadInProgress) return;
    _loadInProgress = true;

    final storageRepo = context.read<StorageRepository>();
    final smallItemRepo = context.read<StorageSmallItemRepository>();

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await retryOnFailure(() async {
        final allStorages = await storageRepo.getAll();
        final email = context.read<AuthService>().user?.email;
        final storages = DemoMode.filterStorages(email, allStorages);
        final remainingByStorage = <int, int>{};
        for (final s in storages) {
          remainingByStorage[s.id] =
              await storageRepo.getRemainingCount(s.id);
        }

        final options = await smallItemRepo.getAll();
        final nameMap = DemoMode.filterSmallItemNames(
          email,
          {for (var o in options) o.id: o.name},
        );

        if (!mounted) return;
        cache.set(
          cacheKey,
          _StorageListCache(
            storages: storages,
            remainingByStorage: remainingByStorage,
            smallItemNames: nameMap,
          ),
        );
        setState(() {
          _storages = storages;
          _remainingByStorage = remainingByStorage;
          _smallItemNames = nameMap;
          _loading = false;
        });
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = toUserFriendlyError(e);
          _loading = false;
        });
      }
    } finally {
      _loadInProgress = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: FullPageLoadingPlaceholder());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _load,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _storages.length,
          itemBuilder: (context, index) {
            final s = _storages[index];
            final remaining = _remainingByStorage[s.id] ?? 0;
            final smallItemStr = s.storageSmallItemIds
                .map((id) => _smallItemNames[id] ?? id.toString())
                .join('、');
            final title = smallItemStr.isNotEmpty
                ? '${s.customerName} · $smallItemStr'
                : s.customerName;
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                title: Text(title),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('¥${s.amount.toStringAsFixed(0)} · 剩余 $remaining 次'),
                    if ((s.remark ?? '').isNotEmpty)
                      Text(
                        s.remark ?? '',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
                trailing: const Icon(Icons.arrow_forward),
                onTap: () async {
                  await context.push('/storage/${s.id}');
                  if (mounted) _load();
                },
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/storage/new');
          if (mounted) _load();
        },
        icon: const Icon(Icons.add, size: 28),
        label: const Text('新建储值', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
