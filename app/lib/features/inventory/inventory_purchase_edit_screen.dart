import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/data_cache.dart';
import '../../core/data_refresh.dart';
import '../../core/demo_mode.dart';
import '../../core/error_message.dart';
import '../../core/retry_helper.dart';
import '../auth/auth_service.dart';
import '../storage_options/storage_big_item_repository.dart';
import '../storage_options/storage_small_item_repository.dart';
import 'inventory_models.dart';
import 'inventory_purchase_repository.dart';
import 'widgets/quantity_stepper.dart';
import 'widgets/inventory_void_dialog.dart';

class InventoryPurchaseEditScreen extends StatefulWidget {
  const InventoryPurchaseEditScreen({
    super.key,
    this.purchaseId,
    this.initialReadOnly = false,
  });

  final int? purchaseId;

  /// 已有记录默认可从只读浏览态进入，避免误触修改。
  final bool initialReadOnly;

  @override
  State<InventoryPurchaseEditScreen> createState() =>
      _InventoryPurchaseEditScreenState();
}

class _InventoryPurchaseEditScreenState
    extends State<InventoryPurchaseEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _totalAmountController;
  late TextEditingController _remarkController;

  String _bigItemName = '';
  int _smallItemId = 0;
  int _quantity = 0;
  DateTime _purchaseDate = DateTime.now();
  String _existingCode = '';
  List<StorageBigItemOption> _bigItemOptions = [];
  List<StorageSmallItemOption> _smallItemOptions = [];
  final List<_PurchaseLineDraft> _lines = [];
  int _activeLineIndex = 0;
  bool _hasLineDataMismatch = false;
  bool _loading = false;
  late bool _isEditing;
  String? _error;
  InventoryPurchaseRecordModel? _loadedRecord;

  String _cacheKeyBig(BuildContext context) =>
      DemoMode.inventoryBigOptionsCacheKey(
        context.read<AuthService>().user?.email,
      );

  String _cacheKeySmall(BuildContext context) =>
      DemoMode.inventorySmallOptionsCacheKey(
        context.read<AuthService>().user?.email,
      );

  @override
  void initState() {
    super.initState();
    _totalAmountController = TextEditingController(text: '0');
    _remarkController = TextEditingController();
    _isEditing = !widget.initialReadOnly || widget.purchaseId == null;
    _loadOptions();
    if (widget.purchaseId != null) {
      _loadPurchase();
    }
  }

  @override
  void dispose() {
    _totalAmountController.dispose();
    _remarkController.dispose();
    super.dispose();
  }

  int? _getBigItemId() {
    if (_bigItemName.isEmpty) return null;
    try {
      return _bigItemOptions.firstWhere((b) => b.name == _bigItemName).id;
    } catch (_) {
      return null;
    }
  }

  List<StorageSmallItemOption> get _smallItemsUnderBigItem {
    final bigId = _getBigItemId();
    return _smallItemOptions.where((s) => s.storageBigItemId == bigId).toList();
  }

  String _smallItemName(int id) {
    for (final option in _smallItemOptions) {
      if (option.id == id) return option.name;
    }
    return '小项 #$id';
  }

  void _writeActiveLineFromEditor() {
    if (_activeLineIndex < 0 || _activeLineIndex >= _lines.length) return;
    _lines[_activeLineIndex] = _PurchaseLineDraft(
      bigItemName: _bigItemName,
      smallItemId: _smallItemId,
      quantity: _quantity,
    );
  }

  void _loadActiveLineIntoEditor() {
    if (_lines.isEmpty) return;
    _activeLineIndex = _activeLineIndex.clamp(0, _lines.length - 1);
    final line = _lines[_activeLineIndex];
    _bigItemName = line.bigItemName;
    _smallItemId = line.smallItemId;
    _quantity = line.quantity;
  }

  void _ensureInitialLine() {
    if (_lines.isNotEmpty || _bigItemOptions.isEmpty) return;
    final bigName = _bigItemOptions.first.name;
    final bigId = _bigItemOptions.first.id;
    final small = _smallItemOptions.where((o) => o.storageBigItemId == bigId);
    _lines.add(
      _PurchaseLineDraft(
        bigItemName: bigName,
        smallItemId: small.isEmpty ? 0 : small.first.id,
        quantity: 1,
      ),
    );
    _activeLineIndex = 0;
    _loadActiveLineIntoEditor();
  }

  void _selectLine(int index) {
    _writeActiveLineFromEditor();
    setState(() {
      _activeLineIndex = index;
      _loadActiveLineIntoEditor();
    });
  }

  void _addLine() {
    _writeActiveLineFromEditor();
    final bigName = _bigItemOptions.isEmpty ? '' : _bigItemOptions.first.name;
    final bigId = _bigItemOptions.isEmpty ? null : _bigItemOptions.first.id;
    final small = _smallItemOptions.where((o) => o.storageBigItemId == bigId);
    setState(() {
      _lines.add(
        _PurchaseLineDraft(
          bigItemName: bigName,
          smallItemId: small.isEmpty ? 0 : small.first.id,
          quantity: 1,
        ),
      );
      _activeLineIndex = _lines.length - 1;
      _loadActiveLineIntoEditor();
    });
  }

  void _removeLine(int index) {
    if (_lines.length <= 1) return;
    _writeActiveLineFromEditor();
    setState(() {
      _lines.removeAt(index);
      if (_activeLineIndex >= _lines.length) {
        _activeLineIndex = _lines.length - 1;
      } else if (index < _activeLineIndex) {
        _activeLineIndex -= 1;
      }
      _loadActiveLineIntoEditor();
    });
  }

  Future<void> _loadOptions() async {
    final cache = context.read<DataCache>();
    final keyBig = _cacheKeyBig(context);
    final keySmall = _cacheKeySmall(context);
    final email = context.read<AuthService>().user?.email;
    var big = cache.get<List<StorageBigItemOption>>(keyBig);
    var small = cache.get<List<StorageSmallItemOption>>(keySmall);
    if (big == null || small == null) {
      final bigRepo = context.read<StorageBigItemRepository>();
      final smallRepo = context.read<StorageSmallItemRepository>();
      final allBig = await retryOnFailure(() => bigRepo.getAll());
      final allSmall = await retryOnFailure(() => smallRepo.getAll());
      big = allBig;
      small = DemoMode.filterSmallItemOptions(email, allSmall);
      if (mounted) {
        cache.set(keyBig, big, ttl: const Duration(hours: 1));
        cache.set(keySmall, small, ttl: const Duration(hours: 1));
      }
    }
    if (mounted) {
      final bigList = big;
      final smallList = small;
      setState(() {
        _bigItemOptions = bigList;
        _smallItemOptions = smallList;
        if (_bigItemName.isEmpty && bigList.isNotEmpty) {
          _bigItemName = bigList.first.name;
        }
        int? bigId;
        for (final b in bigList) {
          if (b.name == _bigItemName) {
            bigId = b.id;
            break;
          }
        }
        if (bigId == null && bigList.isNotEmpty) bigId = bigList.first.id;
        final underBig = smallList
            .where((s) => s.storageBigItemId == bigId)
            .toList();
        if (_smallItemId == 0 && underBig.isNotEmpty) {
          _smallItemId = underBig.first.id;
        } else if (_smallItemId != 0 &&
            !underBig.any((s) => s.id == _smallItemId)) {
          _smallItemId = underBig.isNotEmpty ? underBig.first.id : 0;
        }
        _ensureInitialLine();
      });
    }
  }

  Future<void> _addBigItem() async {
    final controller = TextEditingController(text: _bigItemName);
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
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      final repo = context.read<StorageBigItemRepository>();
      final opt = await retryOnFailure(() => repo.getOrCreate(name));
      if (!mounted) return;
      final cache = context.read<DataCache>();
      setState(() {
        if (_bigItemOptions.every((o) => o.id != opt.id)) {
          _bigItemOptions = [..._bigItemOptions, opt]
            ..sort((a, b) => a.name.compareTo(b.name));
        }
        _bigItemName = opt.name;
        final underBig = _smallItemsUnderBigItem;
        if (!underBig.any((item) => item.id == _smallItemId)) {
          _smallItemId = underBig.isEmpty ? 0 : underBig.first.id;
        }
        _writeActiveLineFromEditor();
      });
      cache.set(
        _cacheKeyBig(context),
        _bigItemOptions,
        ttl: const Duration(hours: 1),
      );
      // 让储值编辑等其它页面的下拉选项也能刷新
      context.read<DataRefreshNotifier>().invalidateStorageOptions();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('新增大项失败：${toUserFriendlyError(e)}')),
      );
    }
  }

  /// 从选择器内调用，当前大项下无小项时直接弹窗新增；返回新小项 id 或 null
  Future<int?> _addSmallItemFromPicker() async {
    final bigName = _bigItemName.isNotEmpty ? _bigItemName : '当前大项';
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('新增小项（$bigName）'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '小项名称',
            hintText: '如：面膜、精华液',
          ),
          autofocus: true,
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
    if (name == null || name.trim().isEmpty || !mounted) return null;
    try {
      final repo = context.read<StorageSmallItemRepository>();
      final bigId = _getBigItemId();
      final opt = await retryOnFailure(
        () => repo.getOrCreate(name, storageBigItemId: bigId),
      );
      if (!mounted) return null;
      final cache = context.read<DataCache>();
      setState(() {
        if (_smallItemOptions.every((o) => o.id != opt.id)) {
          _smallItemOptions = [..._smallItemOptions, opt]
            ..sort((a, b) => a.name.compareTo(b.name));
        }
        _smallItemId = opt.id;
        _writeActiveLineFromEditor();
      });
      cache.set(
        _cacheKeySmall(context),
        _smallItemOptions,
        ttl: const Duration(hours: 1),
      );
      context.read<DataRefreshNotifier>().invalidateStorageOptions();
      return opt.id;
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('新增小项失败：${toUserFriendlyError(e)}')),
      );
      return null;
    }
  }

  Future<void> _addSmallItem() async {
    final result = await _addSmallItemFromPicker();
    if (result != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已新增小项')));
    }
  }

  Future<void> _pickSmallItem() async {
    if (_bigItemOptions.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先新增大项')));
      return;
    }
    final currentId = _smallItemId;
    final optionsUnderBig = _smallItemsUnderBigItem;
    if (optionsUnderBig.isEmpty) {
      if (!mounted) return;
      final added = await _addSmallItemFromPicker();
      if (added != null && mounted) {
        setState(() {
          _smallItemId = added;
        });
      }
      return;
    }
    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final searchController = TextEditingController();
        List<StorageSmallItemOption> filtered = List.of(optionsUnderBig);
        return StatefulBuilder(
          builder: (ctx, setModalState) => SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.5,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: TextField(
                        controller: searchController,
                        decoration: const InputDecoration(
                          labelText: '搜索储值小项',
                          hintText: '输入名称关键字',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (value) {
                          final q = value.trim();
                          setModalState(() {
                            if (q.isEmpty) {
                              filtered = List.of(optionsUnderBig);
                            } else {
                              filtered = optionsUnderBig
                                  .where(
                                    (o) =>
                                        o.name.contains(q) ||
                                        o.name.toLowerCase().contains(
                                          q.toLowerCase(),
                                        ),
                                  )
                                  .toList();
                            }
                          });
                        },
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.add_circle_outline),
                      title: const Text('新增小项'),
                      onTap: () async {
                        Navigator.pop(ctx);
                        final added = await _addSmallItemFromPicker();
                        if (added != null && mounted) {
                          setState(() {
                            _smallItemId = added;
                          });
                        }
                      },
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (ctx, index) {
                          final opt = filtered[index];
                          final selected = opt.id == currentId;
                          return ListTile(
                            leading: Icon(
                              selected
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              color: selected
                                  ? Theme.of(ctx).colorScheme.primary
                                  : null,
                            ),
                            title: Text(opt.name),
                            onTap: () => Navigator.pop(ctx, opt.id),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    if (result != null && mounted) {
      setState(() {
        _smallItemId = result;
        _writeActiveLineFromEditor();
      });
    }
  }

  Future<void> _loadPurchase() async {
    final repo = context.read<InventoryPurchaseRepository>();
    final p = await retryOnFailure(() => repo.getById(widget.purchaseId!));
    if (p != null && mounted) {
      setState(() {
        _loadedRecord = p;
        _existingCode = p.code;
        _purchaseDate = p.purchaseDate;
        _totalAmountController.text = p.totalAmount.toStringAsFixed(0);
        _remarkController.text = p.remark ?? '';
        _hasLineDataMismatch = !p.hasAlignedItems;
        _lines
          ..clear()
          ..addAll(
            List.generate(
              p.itemCount,
              (index) => _PurchaseLineDraft(
                bigItemName: p.storageBigItems[index],
                smallItemId: p.storageSmallItemIds[index],
                quantity: p.quantities[index],
              ),
            ),
          );
        if (_lines.isNotEmpty) {
          _activeLineIndex = 0;
          _loadActiveLineIntoEditor();
        } else if (!_hasLineDataMismatch) {
          _ensureInitialLine();
        }
      });
    }
  }

  _PurchaseLineDraft _lineForDisplay(int index) {
    if (index == _activeLineIndex) {
      return _PurchaseLineDraft(
        bigItemName: _bigItemName,
        smallItemId: _smallItemId,
        quantity: _quantity,
      );
    }
    return _lines[index];
  }

  int get _draftTotalQuantity {
    var total = 0;
    for (var index = 0; index < _lines.length; index++) {
      total += _lineForDisplay(index).quantity;
    }
    return total;
  }

  bool _sameList<T>(List<T> left, List<T> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  Widget _buildActiveProductEditor(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 16),
          const _PurchaseStepLabel(
            step: 1,
            title: '选择商品大项',
            description: '先选择商品所属系列或类别',
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: ValueKey('purchase-line-$_activeLineIndex-$_bigItemName'),
            initialValue: _bigItemOptions.any((o) => o.name == _bigItemName)
                ? _bigItemName
                : (_bigItemOptions.isNotEmpty
                      ? _bigItemOptions.first.name
                      : null),
            decoration: const InputDecoration(
              labelText: '大项',
              hintText: '请选择大项',
            ),
            isExpanded: true,
            items: _bigItemOptions
                .map(
                  (option) => DropdownMenuItem(
                    value: option.name,
                    child: Text(option.name, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: !_isEditing
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() {
                      _bigItemName = value;
                      final underBig = _smallItemsUnderBigItem;
                      if (!underBig.any((item) => item.id == _smallItemId)) {
                        _smallItemId = underBig.isNotEmpty
                            ? underBig.first.id
                            : 0;
                      }
                      _writeActiveLineFromEditor();
                    });
                  },
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _loading ? null : _addBigItem,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('没有合适的大项？新增大项'),
            ),
          ),
          const SizedBox(height: 8),
          const _PurchaseStepLabel(
            step: 2,
            title: '选择具体商品（小项）',
            description: '小项会根据上面选择的大项自动筛选',
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _loading || !_isEditing ? null : _pickSmallItem,
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _smallItemId > 0
                          ? _smallItemName(_smallItemId)
                          : '请选择商品小项',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _loading ? null : _addSmallItem,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('没有这个商品？新增小项'),
            ),
          ),
          const SizedBox(height: 8),
          const _PurchaseStepLabel(
            step: 3,
            title: '填写本次进货数量',
            description: '只填写当前这个商品的件数',
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              QuantityStepper(
                value: _quantity,
                enabled: _isEditing,
                onChanged: (value) => setState(() {
                  _quantity = value;
                  _writeActiveLineFromEditor();
                }),
              ),
              const SizedBox(width: 12),
              Text('件', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_hasLineDataMismatch) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该历史记录的商品数据不完整，为避免丢失内容，暂不允许保存')),
      );
      return;
    }
    _writeActiveLineFromEditor();
    if (_lines.isEmpty || _lines.any((line) => line.smallItemId <= 0)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请为每条进货明细选择小项')));
      return;
    }
    if (_lines.any((line) => line.quantity <= 0)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('每条进货明细的数量都必须大于 0')));
      return;
    }
    final smallItemIds = _lines.map((line) => line.smallItemId).toList();
    if (smallItemIds.toSet().length != smallItemIds.length) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('同一种商品只需添加一次，请合并数量后再保存')));
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repo = context.read<InventoryPurchaseRepository>();
      final totalAmount = double.tryParse(_totalAmountController.text) ?? 0;

      final record = InventoryPurchaseRecordModel(
        id: widget.purchaseId ?? 0,
        code: widget.purchaseId != null ? _existingCode : '',
        purchaseDate: _purchaseDate,
        storageBigItems: _lines.map((line) => line.bigItemName).toList(),
        storageSmallItemIds: _lines.map((line) => line.smallItemId).toList(),
        quantities: _lines.map((line) => line.quantity).toList(),
        totalAmount: totalAmount,
        occurredAt: combineInventoryDateAndTime(
          _purchaseDate,
          _loadedRecord?.occurredAt,
        ),
        occurredAtEstimated: _loadedRecord?.occurredAtEstimated ?? false,
        remark: _remarkController.text.trim().isEmpty
            ? null
            : _remarkController.text.trim(),
      );

      final saved = widget.purchaseId != null
          ? await repo.update(record)
          : await repo.create(record);

      if (!saved.hasAlignedItems ||
          !_sameList(saved.storageBigItems, record.storageBigItems) ||
          !_sameList(saved.storageSmallItemIds, record.storageSmallItemIds) ||
          !_sameList(saved.quantities, record.quantities)) {
        throw StateError('数据库返回的进货明细与提交内容不一致');
      }

      if (mounted) {
        context.read<DataRefreshNotifier>().invalidateInventory();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '进货成功：${saved.itemCount} 种商品，共 ${saved.quantities.fold<int>(0, (sum, value) => sum + value)} 件已加入库存',
            ),
          ),
        );
        context.pop(saved.id);
      }
    } catch (e) {
      if (mounted) {
        final message = toUserFriendlyError(e);
        setState(() {
          _error = '保存失败：$message';
          _loading = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败：$message')));
      }
    }
  }

  Future<void> _voidPurchase() async {
    final record = _loadedRecord;
    if (record == null || record.isVoided) return;
    final totalQuantity = record.quantities.fold<int>(
      0,
      (sum, quantity) => sum + quantity,
    );
    final reason = await showInventoryVoidDialog(
      context,
      title: '撤销进货单',
      impact: '撤销后，本单 ${record.itemCount} 种商品、共 $totalQuantity 件将从库存中扣回。',
    );
    if (reason == null || !mounted) return;
    setState(() => _loading = true);
    try {
      final voided = await context
          .read<InventoryPurchaseRepository>()
          .voidRecord(record.id, reason: reason);
      if (!mounted) return;
      setState(() {
        _loadedRecord = voided;
        _isEditing = false;
        _loading = false;
      });
      context.read<DataRefreshNotifier>().invalidateInventory();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已撤销进货单，操作记录已保留')));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = toUserFriendlyError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isExisting = widget.purchaseId != null;
    final isVoided = _loadedRecord?.isVoided ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(!isExisting ? '添加进货' : (_isEditing ? '编辑进货' : '进货详情')),
        actions: [
          if (isExisting && !_isEditing)
            TextButton.icon(
              onPressed: _hasLineDataMismatch || isVoided
                  ? null
                  : () => setState(() => _isEditing = true),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('编辑'),
            )
          else
            TextButton(
              onPressed: _loading ? null : _save,
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存'),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (isExisting && !_isEditing) ...[
              Card(
                color: isVoided
                    ? Theme.of(context).colorScheme.errorContainer
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                child: ListTile(
                  leading: Icon(
                    isVoided
                        ? Icons.history_toggle_off
                        : Icons.visibility_outlined,
                  ),
                  title: Text(isVoided ? '该进货单已撤销' : '当前为浏览态'),
                  subtitle: Text(
                    isVoided
                        ? '撤销时间：${formatInventoryAuditTime(_loadedRecord!.voidedAt!)}\n'
                              '撤销原因：${_loadedRecord!.voidReason ?? '未填写'}'
                        : '内容不可修改；如需调整，请点击右上角“编辑”',
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
            ],
            if (_hasLineDataMismatch) ...[
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: const ListTile(
                  leading: Icon(Icons.warning_amber_rounded),
                  title: Text('该历史进货单的商品数据不完整'),
                  subtitle: Text('大项、小项和数量无法一一对应。为避免继续丢失数据，本记录仅允许浏览。'),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '进货信息',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('进货日期'),
                      subtitle: Text(
                        '${_purchaseDate.year}-${_purchaseDate.month.toString().padLeft(2, '0')}-${_purchaseDate.day.toString().padLeft(2, '0')}',
                      ),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: !_isEditing
                          ? null
                          : () async {
                              final d = await pickInventoryBusinessDate(
                                context,
                                current: _purchaseDate,
                                warnAboutReordering: isExisting,
                              );
                              if (d != null) setState(() => _purchaseDate = d);
                            },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _totalAmountController,
                      enabled: _isEditing,
                      decoration: const InputDecoration(
                        labelText: '总金额（元）',
                        hintText: '可选',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                      ],
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (text.isEmpty) return null;
                        final amount = double.tryParse(text);
                        if (amount == null || amount < 0) {
                          return '请输入正确的金额';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _remarkController,
                      enabled: _isEditing,
                      decoration: const InputDecoration(
                        labelText: '备注',
                        hintText: '可选',
                      ),
                      maxLines: 2,
                    ),
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
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '本单商品',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${_lines.length} 种 · $_draftTotalQuantity 件',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primaryContainer.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.lightbulb_outline),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '一张进货单可以加入多种商品。每种商品都要依次选择“大项 → 小项”，再填写它的进货数量。',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ..._lines.asMap().entries.map((entry) {
                      final index = entry.key;
                      final line = _lineForDisplay(index);
                      final selected = index == _activeLineIndex;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        color: selected
                            ? Theme.of(context).colorScheme.primaryContainer
                                  .withValues(alpha: 0.3)
                            : null,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: selected
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outlineVariant,
                            width: selected ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            ListTile(
                              onTap: _isEditing
                                  ? () => _selectLine(index)
                                  : null,
                              leading: CircleAvatar(
                                child: Text('${index + 1}'),
                              ),
                              title: Text(
                                '商品 ${index + 1}：${_smallItemName(line.smallItemId)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                '${line.bigItemName} → ${_smallItemName(line.smallItemId)} · ${line.quantity} 件',
                              ),
                              trailing: _isEditing && _lines.length > 1
                                  ? IconButton(
                                      tooltip: '删除商品 ${index + 1}',
                                      onPressed: () => _removeLine(index),
                                      icon: const Icon(Icons.delete_outline),
                                    )
                                  : (!_isEditing
                                        ? null
                                        : Icon(
                                            selected
                                                ? Icons.expand_less
                                                : Icons.expand_more,
                                          )),
                            ),
                            if (_isEditing && selected)
                              _buildActiveProductEditor(context),
                          ],
                        ),
                      );
                    }),
                    if (_isEditing)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _loading ? null : _addLine,
                          icon: const Icon(Icons.add_circle_outline),
                          label: const Text('继续添加另一种商品'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (isExisting && !_isEditing && !isVoided) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: _loading ? null : _voidPurchase,
                icon: const Icon(Icons.undo),
                label: const Text('撤销进货并保留记录'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PurchaseLineDraft {
  const _PurchaseLineDraft({
    required this.bigItemName,
    required this.smallItemId,
    required this.quantity,
  });

  final String bigItemName;
  final int smallItemId;
  final int quantity;
}

class _PurchaseStepLabel extends StatelessWidget {
  const _PurchaseStepLabel({
    required this.step,
    required this.title,
    required this.description,
  });

  final int step;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$step',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
