import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../customer/customer_model.dart';
import '../customer/customer_repository.dart';
import '../inventory/inventory_consumption_repository.dart';
import '../inventory/inventory_models.dart';
import '../inventory/inventory_purchase_repository.dart';
import '../inventory/inventory_supp_in_repository.dart';
import '../inventory/widgets/quantity_stepper.dart';
import '../storage_options/storage_big_item_repository.dart';
import '../storage_options/storage_small_item_repository.dart';
import 'storage_model.dart';
import 'storage_small_item_picker.dart';
import 'storage_repository.dart';
import '../../core/data_cache.dart';
import '../../core/data_refresh.dart';
import '../../core/demo_mode.dart';
import '../../core/error_message.dart';
import '../../core/formula_helper.dart';
import '../../core/write_request_id.dart';
import '../auth/auth_service.dart';

class StorageEditScreen extends StatefulWidget {
  const StorageEditScreen({
    super.key,
    this.storageId,
    this.customerName,
    this.copyFromId,
  });

  final int? storageId;
  final String? customerName;
  final int? copyFromId;

  @override
  State<StorageEditScreen> createState() => _StorageEditScreenState();
}

class _StorageEditScreenState extends State<StorageEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _customerController;
  late TextEditingController _codeController;
  late TextEditingController _amountController;
  late TextEditingController _totalCountController;
  late TextEditingController _remarkController;

  int? _selectedBigItemId;
  List<int> _selectedSmallItemIds = [];
  final Map<int, int> _outQtyBySmallItemId = {};
  bool _doOutboundThisTime = true;

  List<StorageBigItemOption> _bigItemOptions = [];
  List<StorageSmallItemOption> _smallItemOptions = [];
  bool _legacyMultiBigItems = false;
  DateTime _storageDate = DateTime.now();

  /// 保存流程中：遮罩防重复点击并提示「处理中」
  bool _saving = false;
  bool _saveInProgress = false;
  bool _optionsLoading = true;
  String? _optionsError;
  String? _error;
  final String _createRequestId = newWriteRequestId();

  /// 各小项当前库存余额（与保存校验同源），供小项选择器角标与保存时复用
  Map<int, int>? _cachedInventoryBalances;

  /// 后台预取库存进行中（角标处显示「加载中」）
  bool _inventoryBalancesLoading = false;

  /// 与 [_cachedInventoryBalances] 同步，供小项底部弹窗 [ValueListenableBuilder] 在预取完成后刷新
  late final ValueNotifier<Map<int, int>?> _inventoryBalanceNotifier;

  @override
  void initState() {
    super.initState();
    _inventoryBalanceNotifier = ValueNotifier<Map<int, int>?>(null);
    _customerController = TextEditingController(
      text: widget.customerName ?? '',
    );
    _codeController = TextEditingController();
    _amountController = TextEditingController();
    _totalCountController = TextEditingController();
    _remarkController = TextEditingController();
    _amountController.addListener(_onAmountChanged);
    if (widget.customerName != null) {
      _storageDate = DateTime.now();
    }
    _bootstrap();
  }

  static const _cacheKeySmallOptions = 'small_item_options';
  static const _cacheKeyBigOptions = 'big_item_options';
  static String _cacheKeyStorage(int id) => 'storage_$id';

  Future<void> _bootstrap() async {
    if (mounted)
      setState(() {
        _optionsLoading = true;
        _optionsError = null;
      });
    try {
      await _loadOptions();
      if (!mounted) return;
      if (widget.storageId != null) {
        await _loadStorage();
      } else if (widget.copyFromId != null) {
        await _loadCopy();
      }
    } catch (e) {
      if (mounted) setState(() => _optionsError = toUserFriendlyError(e));
    } finally {
      if (mounted) setState(() => _optionsLoading = false);
    }
  }

  Future<void> _loadOptions() async {
    final cache = context.read<DataCache>();
    final auth = context.read<AuthService>();
    final owner = auth.user?.id;
    final revision = cache.revision;
    var smallOptions = cache.get<List<StorageSmallItemOption>>(
      _cacheKeySmallOptions,
    );
    var bigOptions = cache.get<List<StorageBigItemOption>>(_cacheKeyBigOptions);
    if (smallOptions == null || bigOptions == null) {
      final smallRepo = context.read<StorageSmallItemRepository>();
      final bigRepo = context.read<StorageBigItemRepository>();
      final options = await Future.wait<dynamic>([
        smallRepo.getAll(),
        bigRepo.getAll(),
      ]);
      smallOptions = options[0] as List<StorageSmallItemOption>;
      bigOptions = options[1] as List<StorageBigItemOption>;
      if (!mounted || auth.user?.id != owner || cache.revision != revision)
        return;
      cache.set(
        _cacheKeySmallOptions,
        smallOptions,
        ttl: const Duration(hours: 1),
      );
      cache.set(_cacheKeyBigOptions, bigOptions, ttl: const Duration(hours: 1));
    }
    if (!mounted) return;
    final email = context.read<AuthService>().user?.email;
    setState(() {
      _smallItemOptions = DemoMode.filterSmallItemOptions(email, smallOptions!);
      _bigItemOptions = bigOptions!;
    });
    if (widget.storageId == null) {
      _prefetchInventoryBalances();
    }
  }

  void _inferBigItemFromRecord(List<String> bigNames, List<int> smallIds) {
    _legacyMultiBigItems = bigNames.length > 1;
    int? id;
    if (bigNames.isNotEmpty) {
      final name = bigNames.first.trim();
      for (final b in _bigItemOptions) {
        if (b.name == name) {
          id = b.id;
          break;
        }
      }
    }
    if (id == null && smallIds.isNotEmpty) {
      final counts = <int, int>{};
      for (final sid in smallIds) {
        StorageSmallItemOption? o;
        for (final x in _smallItemOptions) {
          if (x.id == sid) {
            o = x;
            break;
          }
        }
        final bid = o?.storageBigItemId;
        if (bid != null) {
          counts[bid] = (counts[bid] ?? 0) + 1;
        }
      }
      if (counts.isNotEmpty) {
        var bestK = counts.keys.first;
        var bestV = counts[bestK]!;
        for (final e in counts.entries) {
          if (e.value > bestV) {
            bestV = e.value;
            bestK = e.key;
          }
        }
        id = bestK;
      }
    }
    _selectedBigItemId = id;
    for (final sid in smallIds) {
      _outQtyBySmallItemId.putIfAbsent(sid, () => 1);
    }
  }

  Future<void> _loadStorage() async {
    final id = widget.storageId!;
    final cache = context.read<DataCache>();
    var s = cache.get<StorageRecordModel>(_cacheKeyStorage(id));
    if (s == null) {
      final repo = context.read<StorageRepository>();
      s = await repo.getById(id);
      if (!mounted) return;
      if (s != null) cache.set(_cacheKeyStorage(id), s);
    }
    if (!mounted) return;
    if (s != null) {
      _customerController.text = s.customerName;
      _codeController.text = s.code;
      _amountController.text = s.amount.toStringAsFixed(0);
      _totalCountController.text = s.totalCount.toString();
      _remarkController.text = s.remark ?? '';
      _selectedSmallItemIds = List.from(s.storageSmallItemIds);
      _storageDate = s.storageDate;
      _inferBigItemFromRecord(s.storageBigItems, s.storageSmallItemIds);
      setState(() {});
    }
  }

  Future<void> _loadCopy() async {
    final id = widget.copyFromId!;
    final cache = context.read<DataCache>();
    var s = cache.get<StorageRecordModel>(_cacheKeyStorage(id));
    if (s == null) {
      final repo = context.read<StorageRepository>();
      s = await repo.getById(id);
      if (!mounted) return;
      if (s != null) cache.set(_cacheKeyStorage(id), s);
    }
    if (!mounted) return;
    if (s != null) {
      _customerController.text = s.customerName;
      _selectedSmallItemIds = List.from(s.storageSmallItemIds);
      _remarkController.text = s.remark ?? '';
      _amountController.clear();
      _totalCountController.clear();
      _storageDate = DateTime.now();
      _inferBigItemFromRecord(s.storageBigItems, s.storageSmallItemIds);
      setState(() {});
    }
  }

  List<StorageSmallItemOption> get _pickerSmallOptions {
    final bid = _selectedBigItemId;
    if (bid == null) return [];
    final under = _smallItemOptions
        .where((s) => s.storageBigItemId == bid)
        .toList();
    final orphans = _smallItemOptions
        .where(
          (s) =>
              _selectedSmallItemIds.contains(s.id) && s.storageBigItemId != bid,
        )
        .toList();
    final byId = <int, StorageSmallItemOption>{};
    for (final o in [...under, ...orphans]) {
      byId[o.id] = o;
    }
    final list = byId.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  String? _selectedBigName() {
    final id = _selectedBigItemId;
    if (id == null) return null;
    for (final b in _bigItemOptions) {
      if (b.id == id) return b.name;
    }
    return null;
  }

  void _pruneOutQtyMap() {
    _outQtyBySmallItemId.removeWhere(
      (k, _) => !_selectedSmallItemIds.contains(k),
    );
  }

  void _onBigItemSelected(StorageBigItemOption opt) {
    setState(() {
      _selectedBigItemId = opt.id;
      _selectedSmallItemIds.removeWhere((sid) {
        StorageSmallItemOption? o;
        for (final x in _smallItemOptions) {
          if (x.id == sid) {
            o = x;
            break;
          }
        }
        return o == null || o.storageBigItemId != opt.id;
      });
      _pruneOutQtyMap();
    });
    if (widget.storageId == null) {
      _prefetchInventoryBalances();
    }
  }

  /// 后台拉取全量库存余额，供小项「剩余库存」角标与保存校验复用（并行请求降低等待）
  void _prefetchInventoryBalances() {
    if (!mounted || widget.storageId != null) return;
    setState(() => _inventoryBalancesLoading = true);
    Future.microtask(() async {
      if (!mounted || widget.storageId != null) return;
      try {
        final m = await _computeInventoryBalances();
        if (mounted) {
          _inventoryBalanceNotifier.value = m;
          setState(() {
            _cachedInventoryBalances = m;
            _inventoryBalancesLoading = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _inventoryBalancesLoading = false);
      }
    });
  }

  void _beginSavingOverlay() {
    if (!mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
  }

  void _endSavingOverlay() {
    if (!mounted) return;
    setState(() => _saving = false);
  }

  @override
  void dispose() {
    _inventoryBalanceNotifier.dispose();
    _customerController.dispose();
    _amountController.removeListener(_onAmountChanged);
    _codeController.dispose();
    _amountController.dispose();
    _totalCountController.dispose();
    _remarkController.dispose();
    super.dispose();
  }

  void _onAmountChanged() {
    final text = _amountController.text;
    if (!text.endsWith('=') || text.length <= 1) return;
    const longFormulaThreshold = 60;
    if (text.length > longFormulaThreshold) {
      compute(tryParseFormula, text).then((result) {
        if (!mounted) return;
        if (result != null && result >= 0) {
          _amountController
            ..removeListener(_onAmountChanged)
            ..text = result.toStringAsFixed(
              result == result.roundToDouble() ? 0 : 2,
            )
            ..selection = TextSelection.collapsed(
              offset: _amountController.text.length,
            )
            ..addListener(_onAmountChanged);
        }
      });
      return;
    }
    final result = tryParseFormula(text);
    if (result != null && result >= 0) {
      _amountController
        ..removeListener(_onAmountChanged)
        ..text = result.toStringAsFixed(
          result == result.roundToDouble() ? 0 : 2,
        )
        ..selection = TextSelection.collapsed(
          offset: _amountController.text.length,
        )
        ..addListener(_onAmountChanged);
    }
  }

  Future<Map<int, int>> _computeInventoryBalances() async {
    final purchaseRepo = context.read<InventoryPurchaseRepository>();
    final suppInRepo = context.read<InventorySuppInRepository>();
    final consumptionRepo = context.read<InventoryConsumptionRepository>();
    final smallItemRepo = context.read<StorageSmallItemRepository>();

    final auth = context.read<AuthService>();
    final owner = auth.user?.id;
    final batch = await Future.wait([
      purchaseRepo.getAll(),
      suppInRepo.getAll(),
      consumptionRepo.getAll(),
      smallItemRepo.getAll(),
    ]);
    if (auth.user?.id != owner) throw StateError('账号已变化，请重新打开页面');
    final email = auth.user?.email;
    final scoped = DemoMode.scopeInventoryRaw(
      email: email,
      purchases: batch[0] as List<InventoryPurchaseRecordModel>,
      suppIn: batch[1] as List<InventorySuppInRecordModel>,
      consumptions: batch[2] as List<InventoryConsumptionRecordModel>,
      smallOptions: batch[3] as List<StorageSmallItemOption>,
    );
    return DemoMode.computeInventoryBalances(
      purchases: scoped.purchases,
      suppIn: scoped.suppIn,
      consumptions: scoped.consumptions,
      smallOptions: scoped.smallOptions,
    );
  }

  Future<Map<int, int>> _fetchInventoryBalances() =>
      _computeInventoryBalances();

  Future<void> _save() async {
    if (_saveInProgress ||
        _saving ||
        _optionsLoading ||
        _optionsError != null) {
      return;
    }
    _saveInProgress = true;
    try {
      await _saveInternal();
    } catch (e) {
      if (mounted) setState(() => _error = toUserFriendlyError(e));
    } finally {
      _saveInProgress = false;
      if (mounted) _endSavingOverlay();
    }
  }

  Future<void> _saveInternal() async {
    if (!_formKey.currentState!.validate()) return;

    final customerName = _customerController.text.trim();
    if (customerName.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请填写客户姓名')));
      return;
    }

    if (_selectedBigItemId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请选择储值大项')));
      return;
    }
    if (_selectedSmallItemIds.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请至少选择一个储值小项')));
      return;
    }

    final bigId = _selectedBigItemId!;
    for (final sid in _selectedSmallItemIds) {
      StorageSmallItemOption? o;
      for (final x in _smallItemOptions) {
        if (x.id == sid) {
          o = x;
          break;
        }
      }
      if (o == null || o.storageBigItemId != bigId) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('所选小项与当前大项不匹配，请重新选择')));
        return;
      }
    }

    final customerRepo = context.read<CustomerRepository>();
    final CustomerModel? existingCustomer = await customerRepo.getByName(
      customerName,
    );
    if (existingCustomer == null && widget.storageId == null) {
      final goEdit = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('客户不存在'),
          content: Text('客户「$customerName」尚未录入，请先新建客户后再新增储值。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('去新建客户'),
            ),
          ],
        ),
      );
      if (goEdit == true && mounted) {
        await context.push(
          '/customer/new',
          extra: {'initialName': customerName},
        );
      }
      return;
    }

    final amount =
        double.tryParse(_amountController.text) ??
        tryParseFormula(_amountController.text);
    final totalCountText = _totalCountController.text.trim();
    final int? totalCount = totalCountText.isEmpty
        ? 0
        : int.tryParse(totalCountText);
    if (amount == null || amount < 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入有效的储值金额')));
      return;
    }
    if (totalCount == null || totalCount < 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入有效的总储值次数（≥0）')));
      return;
    }

    final isNew = widget.storageId == null;
    if (isNew && _doOutboundThisTime) {
      if (_cachedInventoryBalances == null) {
        _beginSavingOverlay();
      }
      final balances =
          _cachedInventoryBalances ?? await _fetchInventoryBalances();
      if (mounted && _cachedInventoryBalances == null) {
        _inventoryBalanceNotifier.value = balances;
        setState(() => _cachedInventoryBalances = balances);
      }
      final deficits = <String>[];
      for (final id in _selectedSmallItemIds) {
        final q = _outQtyBySmallItemId[id] ?? 1;
        if (q <= 0) continue;
        final bal = balances[id] ?? 0;
        if (q > bal) {
          String name = id.toString();
          for (final x in _smallItemOptions) {
            if (x.id == id) {
              name = x.name;
              break;
            }
          }
          deficits.add('$name（库存 $bal，需出库 $q）');
        }
      }
      if (deficits.isNotEmpty) {
        if (!mounted) return;
        _endSavingOverlay();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('库存不足：${deficits.join('；')}'),
            duration: const Duration(seconds: 6),
          ),
        );
        return;
      }
    }

    final bigName = _selectedBigName();
    if (bigName == null || bigName.isEmpty) {
      if (_saving) _endSavingOverlay();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法解析大项名称')));
      return;
    }

    if (!_saving) {
      _beginSavingOverlay();
    }

    if (!mounted) return;
    try {
      CustomerModel? cust = existingCustomer;
      if (cust == null || cust.name != customerName) {
        cust = await customerRepo.getByName(customerName);
      }
      if (cust == null) {
        await customerRepo.create(CustomerModel(name: customerName));
        cust = await customerRepo.getByName(customerName);
      }

      final storageRepo = context.read<StorageRepository>();
      final existing = widget.storageId != null
          ? await storageRepo.getById(widget.storageId!)
          : null;
      final code = (widget.storageId != null && existing != null)
          ? existing.code
          : '';

      final record = StorageRecordModel(
        id: widget.storageId ?? 0,
        code: code,
        customerName: customerName,
        storageBigItems: [bigName],
        storageSmallItemIds: List.from(_selectedSmallItemIds),
        amount: amount,
        totalCount: totalCount,
        storageDate: _storageDate,
        remark: _remarkController.text.trim().isEmpty
            ? null
            : _remarkController.text.trim(),
        clientRequestId: existing?.clientRequestId ?? _createRequestId,
      );

      final StorageRecordModel saved = widget.storageId != null
          ? await storageRepo.update(record)
          : await storageRepo.create(record);

      if (isNew && _doOutboundThisTime) {
        final consumptionRepo = context.read<InventoryConsumptionRepository>();
        final remarkBase = '自动出库 · $customerName';
        final toInsert = <InventoryConsumptionRecordModel>[];
        for (var index = 0; index < _selectedSmallItemIds.length; index++) {
          final id = _selectedSmallItemIds[index];
          final q = _outQtyBySmallItemId[id] ?? 1;
          if (q <= 0) continue;
          toInsert.add(
            InventoryConsumptionRecordModel(
              id: 0,
              consumptionDate: _storageDate,
              storageSmallItemId: id,
              quantity: q,
              remark: remarkBase,
              sourceStorageRecordId: saved.id,
              clientRequestId: childWriteRequestId(_createRequestId, index),
            ),
          );
        }
        try {
          if (toInsert.isNotEmpty) {
            await consumptionRepo.createBatch(toInsert);
          }
        } catch (e) {
          if (mounted) {
            _endSavingOverlay();
            setState(() {
              _error = toUserFriendlyError(e);
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '储值已保存，但库存出库写入失败：${toUserFriendlyError(e)}。请到库存管理中核对并手工补出库。',
                ),
                duration: const Duration(seconds: 8),
              ),
            );
            context
                .read<DataRefreshNotifier>()
                .invalidateStorageConsumptionAndInventory();
            context.pop();
          }
          return;
        }
      }

      if (mounted) {
        final refresh = context.read<DataRefreshNotifier>();
        final didAutoOutbound =
            isNew &&
            _doOutboundThisTime &&
            _selectedSmallItemIds.any(
              (id) => (_outQtyBySmallItemId[id] ?? 1) > 0,
            );
        if (didAutoOutbound) {
          refresh.invalidateStorageConsumptionAndInventory();
        } else {
          refresh.invalidateStorageAndConsumption();
        }
        final msg = widget.storageId != null
            ? '保存成功。修改储值未自动调整库存，请在库存管理中处理。'
            : '保存成功';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            duration: Duration(seconds: widget.storageId != null ? 5 : 2),
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        _endSavingOverlay();
        setState(() {
          _error = toUserFriendlyError(e);
        });
      }
    }
  }

  Future<int?> _addSmallItem(String name) async {
    final bid = _selectedBigItemId;
    if (bid == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请先选择储值大项，再新增小项')));
      }
      return null;
    }
    if (name.trim().isEmpty) return null;
    final repo = context.read<StorageSmallItemRepository>();
    final opt = await repo.getOrCreate(name, storageBigItemId: bid);
    if (mounted) {
      context.read<DataRefreshNotifier>().invalidateStorageOptions();
      setState(() {
        var found = false;
        final next = <StorageSmallItemOption>[];
        for (final o in _smallItemOptions) {
          if (o.id == opt.id) {
            next.add(opt);
            found = true;
          } else {
            next.add(o);
          }
        }
        if (!found) {
          next.add(opt);
        }
        _smallItemOptions = next..sort((a, b) => a.name.compareTo(b.name));
        if (!_selectedSmallItemIds.contains(opt.id)) {
          _selectedSmallItemIds.add(opt.id);
        }
        _outQtyBySmallItemId.putIfAbsent(opt.id, () => 1);
      });
      if (widget.storageId == null) {
        _inventoryBalanceNotifier.value = null;
        setState(() => _cachedInventoryBalances = null);
        _prefetchInventoryBalances();
      }
      return opt.id;
    }
    return null;
  }

  Future<void> _addBigItem() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新增储值大项'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '大项名称',
            hintText: '如：藏红方、御至宝',
          ),
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    try {
      final repo = context.read<StorageBigItemRepository>();
      final opt = await repo.getOrCreate(name);
      if (mounted) {
        context.read<DataRefreshNotifier>().invalidateStorageOptions();
        setState(() {
          if (!_bigItemOptions.any((o) => o.name == opt.name)) {
            _bigItemOptions = [..._bigItemOptions, opt]
              ..sort((a, b) => a.name.compareTo(b.name));
          }
          _selectedBigItemId = opt.id;
          _selectedSmallItemIds.clear();
          _outQtyBySmallItemId.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('添加失败：${toUserFriendlyError(e)}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.storageId != null;
    final bigSelected = _selectedBigItemId != null;
    final showOutboundSection =
        !isEdit && bigSelected && _selectedSmallItemIds.isNotEmpty;

    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? '编辑储值' : '新增储值'),
        actions: [
          TextButton(
            onPressed: _saving || _optionsLoading || _optionsError != null
                ? null
                : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
      body: Stack(
        children: [
          Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_optionsLoading) const LinearProgressIndicator(),
                if (_optionsError != null)
                  MaterialBanner(
                    content: Text(_optionsError!),
                    actions: [
                      TextButton(
                        onPressed: _bootstrap,
                        child: const Text('重新加载'),
                      ),
                    ],
                  ),
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 16),
                ],
                if (_legacyMultiBigItems) ...[
                  MaterialBanner(
                    content: const Text('该储值历史包含多个大项，已按首项或多数小项归属预选，请确认后保存。'),
                    actions: [
                      TextButton(
                        onPressed: () =>
                            setState(() => _legacyMultiBigItems = false),
                        child: const Text('知道了'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '基本信息',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _customerController,
                          decoration: const InputDecoration(
                            labelText: '客户姓名',
                            hintText: '请输入或选择客户，不存在则新建',
                          ),
                          readOnly:
                              widget.customerName != null &&
                              widget.storageId == null,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? '请输入客户姓名'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '储值大项（单选）',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            ..._bigItemOptions.map((opt) {
                              final selected = _selectedBigItemId == opt.id;
                              return ChoiceChip(
                                label: Text(opt.name),
                                selected: selected,
                                onSelected: (_) => _onBigItemSelected(opt),
                              );
                            }),
                            ActionChip(
                              label: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.add, size: 18),
                                  SizedBox(width: 6),
                                  Text('添加大项'),
                                ],
                              ),
                              onPressed: _addBigItem,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '储值小项（多选，随大项展示）',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        if (!bigSelected)
                          Text(
                            '请先选择储值大项',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          )
                        else if (_pickerSmallOptions.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              '该大项下暂无小项，请先在「库存管理」中维护大小项对应关系，或使用下方入口新增。',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.secondary,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        if (bigSelected)
                          StorageSmallItemPicker(
                            options: _pickerSmallOptions,
                            remainingStockBySmallItemId:
                                _cachedInventoryBalances,
                            inventoryStockLoading:
                                !isEdit && _inventoryBalancesLoading,
                            inventoryBalancesListenable: isEdit
                                ? null
                                : _inventoryBalanceNotifier,
                            selectedIds: _selectedSmallItemIds,
                            onAdd: (id) => setState(() {
                              if (!_selectedSmallItemIds.contains(id)) {
                                _selectedSmallItemIds.add(id);
                              }
                              _outQtyBySmallItemId.putIfAbsent(id, () => 1);
                            }),
                            onRemove: (id) => setState(() {
                              _selectedSmallItemIds.remove(id);
                              _outQtyBySmallItemId.remove(id);
                            }),
                            onCreateNew: _addSmallItem,
                          ),
                        if (showOutboundSection) ...[
                          const SizedBox(height: 20),
                          const Divider(),
                          const SizedBox(height: 8),
                          Text(
                            '库存出库',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('本次从库存出库'),
                            subtitle: const Text('关闭则仅保存储值，不扣减库存'),
                            value: _doOutboundThisTime,
                            onChanged: (v) =>
                                setState(() => _doOutboundThisTime = v),
                          ),
                          if (_doOutboundThisTime) ...[
                            const SizedBox(height: 8),
                            Text(
                              '各小项出库数量（默认 1，≤0 则该项不出库）',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 12),
                            ..._selectedSmallItemIds.map((sid) {
                              String label = sid.toString();
                              for (final x in _smallItemOptions) {
                                if (x.id == sid) {
                                  label = x.name;
                                  break;
                                }
                              }
                              final q = _outQtyBySmallItemId[sid] ?? 1;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  children: [
                                    Expanded(child: Text(label)),
                                    QuantityStepper(
                                      value: q,
                                      min: 0,
                                      onChanged: (v) => setState(() {
                                        _outQtyBySmallItemId[sid] = v;
                                      }),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ],
                        const SizedBox(height: 16),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('储值时间'),
                          subtitle: Text(
                            '${_storageDate.year}-${_storageDate.month.toString().padLeft(2, '0')}-${_storageDate.day.toString().padLeft(2, '0')}',
                          ),
                          trailing: const Icon(Icons.calendar_today),
                          onTap: () async {
                            final d = await showDatePicker(
                              context: context,
                              initialDate: _storageDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365),
                              ),
                              locale: const Locale('zh', 'CN'),
                            );
                            if (d != null) setState(() => _storageDate = d);
                          },
                        ),
                        if (widget.storageId != null &&
                            _codeController.text.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _codeController,
                            readOnly: true,
                            decoration: const InputDecoration(
                              labelText: '储值编号',
                              helperText: '系统自动生成，不可修改',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '储值内容',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _amountController,
                          decoration: const InputDecoration(
                            labelText: '储值金额（元）',
                            hintText: '请输入金额或公式，如 1000*0.8=',
                            helperText: '支持公式计算，输入 1000*0.8= 可自动得出 800',
                          ),
                          keyboardType: TextInputType.text,
                          validator: (v) {
                            if (v == null || v.isEmpty) return '请输入储值金额';
                            final num = double.tryParse(v);
                            if (num != null && num >= 0) return null;
                            final formulaResult = tryParseFormula(v);
                            if (formulaResult != null && formulaResult >= 0)
                              return null;
                            return '请输入有效数字或公式（如 1000*0.8=）';
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _totalCountController,
                          decoration: const InputDecoration(
                            labelText: '总储值次数',
                            hintText: '请输入次数（可为0，留空视为0）',
                          ),
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            if (v == null || v.isEmpty) return null;
                            final n = int.tryParse(v);
                            if (n == null || n < 0) return '请输入非负整数（≥0）';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _remarkController,
                          decoration: const InputDecoration(
                            labelText: '备注',
                            hintText: '可选，填写备注信息',
                          ),
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_saving)
            Positioned.fill(
              child: AbsorbPointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.scrim.withValues(alpha: 0.45),
                  ),
                  child: Center(
                    child: Card(
                      elevation: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 28),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 26,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 40,
                              height: 40,
                              child: CircularProgressIndicator(strokeWidth: 3),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              '正在保存…',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '数据正在提交，请稍候\n请勿重复点击保存',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
