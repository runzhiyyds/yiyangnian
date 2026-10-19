import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/data_cache.dart';
import '../../core/demo_mode.dart';
import '../../widgets/loading_placeholder.dart';
import '../../core/data_refresh.dart';
import '../../core/error_message.dart';
import '../../core/repository_read_cache.dart';
import '../../core/retry_helper.dart';
import '../auth/auth_service.dart';
import '../consumption/consumption_repository.dart';
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
  bool _hasLoaded = false;
  String? _error;
  bool _loadInProgress = false;
  bool _reloadQueued = false;
  String? _loadedAccountId;
  String? _observedAccountId;
  late final DataRefreshNotifier _refreshNotifier;
  late final AuthService _authService;

  @override
  void initState() {
    super.initState();
    _refreshNotifier = context.read<DataRefreshNotifier>();
    _refreshNotifier.addListener(_onDataChanged);
    _authService = context.read<AuthService>();
    _observedAccountId = _authService.user?.id;
    _authService.addListener(_onAccountChanged);
    _load();
  }

  void _onDataChanged() {
    if (!mounted) return;
    if (_loadInProgress) {
      _reloadQueued = true;
    } else {
      _load();
    }
  }

  void _onAccountChanged() {
    final accountId = _authService.user?.id;
    if (!mounted || accountId == _observedAccountId) return;
    _observedAccountId = accountId;
    setState(() {
      _storages = [];
      _remainingByStorage = {};
      _smallItemNames = {};
      _hasLoaded = false;
      _loadedAccountId = null;
      _error = null;
      _loading = accountId != null;
    });
    if (accountId != null) _onDataChanged();
  }

  @override
  void dispose() {
    _refreshNotifier.removeListener(_onDataChanged);
    _authService.removeListener(_onAccountChanged);
    super.dispose();
  }

  static const _cacheKeyPrefix = 'storage_list';

  String _listCacheKey() {
    final user = _authService.user;
    return '${_cacheKeyPrefix}_${user?.id ?? 'anonymous'}_${DemoMode.cacheSuffix(user?.email)}';
  }

  Future<void> _load({bool forceRefresh = false}) async {
    if (!mounted) return;
    final cache = context.read<DataCache>();
    final cacheKey = _listCacheKey();
    if (forceRefresh) {
      cache.remove(cacheKey);
      context.read<RepositoryReadCache?>()?.clear();
    }
    final cached = forceRefresh ? null : cache.get<_StorageListCache>(cacheKey);
    if (cached != null) {
      setState(() {
        _storages = cached.storages;
        _remainingByStorage = cached.remainingByStorage;
        _smallItemNames = cached.smallItemNames;
        _hasLoaded = true;
        _loadedAccountId = _authService.user?.id;
        _loading = false;
        _error = null;
      });
      return;
    }
    if (_loadInProgress) {
      _reloadQueued = true;
      return;
    }
    _loadInProgress = true;
    final cacheRevision = cache.revision;
    final accountId = _authService.user?.id;
    bool isCurrentAccount() => mounted && _authService.user?.id == accountId;

    final storageRepo = context.read<StorageRepository>();
    final consumptionRepo = context.read<ConsumptionRepository>();
    final smallItemRepo = context.read<StorageSmallItemRepository>();

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await retryOnFailure(() async {
        final allStorages = await storageRepo.getAll();
        final email = _authService.user?.email;
        final storages = DemoMode.filterStorages(email, allStorages);
        final results = await Future.wait<dynamic>([
          consumptionRepo.getConsumedCountsByStorageIds(
            storages.map((storage) => storage.id),
          ),
          smallItemRepo.getAll(),
        ]);
        final consumedCounts = results[0] as Map<int, int>;
        final remainingByStorage = {
          for (final storage in storages)
            storage.id: storage.totalCount - (consumedCounts[storage.id] ?? 0),
        };
        final options = results[1] as List<StorageSmallItemOption>;
        final nameMap = DemoMode.filterSmallItemNames(email, {
          for (var o in options) o.id: o.name,
        });

        if (!isCurrentAccount() || cache.revision != cacheRevision) return;
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
          _hasLoaded = true;
          _loadedAccountId = accountId;
          _loading = false;
        });
      });
    } catch (e) {
      if (isCurrentAccount()) {
        setState(() {
          _error = toUserFriendlyError(e);
          _loading = false;
        });
      }
    } finally {
      _loadInProgress = false;
      if (mounted && (_reloadQueued || !isCurrentAccount())) {
        _reloadQueued = false;
        if (_authService.user != null) _load();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sameAccount = _loadedAccountId == _authService.user?.id;
    if (_loading && (!_hasLoaded || !sameAccount)) {
      return const Center(child: FullPageLoadingPlaceholder());
    }
    if (_error != null && (!_hasLoaded || !sameAccount)) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => _load(forceRefresh: true),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => _load(forceRefresh: true),
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _storages.length + (_loading || _error != null ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == 0 && _loading) {
              return const LinearProgressIndicator();
            }
            if (index == 0 && _error != null) {
              return MaterialBanner(
                content: Text('刷新失败，显示上次成功加载的储值记录。$_error'),
                actions: [
                  TextButton(
                    onPressed: () => _load(forceRefresh: true),
                    child: const Text('重试'),
                  ),
                ],
              );
            }
            if (_loading || _error != null) index--;
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
        label: const Text(
          '新建储值',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
