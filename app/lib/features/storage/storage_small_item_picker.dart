import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../storage_options/storage_small_item_repository.dart';

/// 储值小项选择器 - 使用底部弹窗，避免移动端输入法遮挡
class StorageSmallItemPicker extends StatelessWidget {
  const StorageSmallItemPicker({
    super.key,
    required this.options,
    this.remainingStockBySmallItemId,
    this.inventoryStockLoading = false,
    this.inventoryBalancesListenable,
    required this.selectedIds,
    required this.onAdd,
    required this.onRemove,
    required this.onCreateNew,
    this.allowCreate = true,
    this.addButtonLabelWhenEmpty,
    this.addButtonLabelWhenNotEmpty,
    this.subtleButton = false,
  });

  final List<StorageSmallItemOption> options;

  /// 各小项剩余库存；null 时不展示角标
  final Map<int, int>? remainingStockBySmallItemId;

  /// true 且 [remainingStockBySmallItemId] 仍为 null 时展示「加载中」（库存预取未完成）
  final bool inventoryStockLoading;

  /// 与父页库存缓存同步；底部弹窗内用 [ValueListenableBuilder] 以便预取完成后刷新角标
  final ValueListenable<Map<int, int>?>? inventoryBalancesListenable;
  final List<int> selectedIds;
  final void Function(int id) onAdd;
  final void Function(int id) onRemove;
  final Future<int?> Function(String name) onCreateNew;
  final bool allowCreate;

  /// 自定义按钮文案：当未选择任何小项时
  final String? addButtonLabelWhenEmpty;

  /// 自定义按钮文案：当已选择小项时
  final String? addButtonLabelWhenNotEmpty;

  /// 是否使用更弱提示的按钮样式（TextButton），避免与主要操作混淆
  final bool subtleButton;

  void _showPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _PickerSheet(
        options: options,
        remainingStockBySmallItemId: remainingStockBySmallItemId,
        inventoryStockLoading: inventoryStockLoading,
        inventoryBalancesListenable: inventoryBalancesListenable,
        selectedIds: selectedIds,
        onAdd: onAdd,
        onRemove: onRemove,
        onCreateNew: onCreateNew,
        allowCreate: allowCreate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedOpts = options
        .where((o) => selectedIds.contains(o.id))
        .toList();

    final String buttonLabel = selectedOpts.isEmpty
        ? (addButtonLabelWhenEmpty ?? '添加储值小项')
        : (addButtonLabelWhenNotEmpty ?? '继续添加');

    final Widget button = subtleButton
        ? Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: Text(buttonLabel),
              onPressed: () => _showPicker(context),
            ),
          )
        : SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: Text(buttonLabel),
              onPressed: () => _showPicker(context),
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selectedOpts.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: selectedOpts.map((opt) {
              final stock = remainingStockBySmallItemId?[opt.id];
              final loading =
                  inventoryStockLoading && remainingStockBySmallItemId == null;
              String label = opt.name;
              if (loading) {
                label = '$label · 加载中…';
              } else if (stock != null) {
                label = '$label · 余$stock';
              }
              return Chip(
                label: Text(label),
                onDeleted: () => onRemove(opt.id),
              );
            }).toList(),
          ),
        if (selectedOpts.isNotEmpty) const SizedBox(height: 12),
        button,
      ],
    );
  }
}

class _PickerSheet extends StatefulWidget {
  final List<StorageSmallItemOption> options;
  final Map<int, int>? remainingStockBySmallItemId;
  final bool inventoryStockLoading;
  final ValueListenable<Map<int, int>?>? inventoryBalancesListenable;
  final List<int> selectedIds;
  final void Function(int id) onAdd;
  final void Function(int id) onRemove;
  final Future<int?> Function(String name) onCreateNew;
  final bool allowCreate;

  const _PickerSheet({
    required this.options,
    this.remainingStockBySmallItemId,
    this.inventoryStockLoading = false,
    this.inventoryBalancesListenable,
    required this.selectedIds,
    required this.onAdd,
    required this.onRemove,
    required this.onCreateNew,
    required this.allowCreate,
  });

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  final _searchController = TextEditingController();
  late List<int> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = List.from(widget.selectedIds);
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildPickerScrollArea(
    BuildContext context,
    ScrollController scrollController,
    List<StorageSmallItemOption> filtered,
    Map<int, int>? balanceMap,
  ) {
    final loadingRow = widget.inventoryStockLoading && balanceMap == null;
    return Column(
      children: [
        if (loadingRow)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '正在加载剩余库存…',
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              if (widget.allowCreate) ...[
                ListTile(
                  leading: const Icon(
                    Icons.add_circle_outline,
                    color: Colors.blue,
                  ),
                  title: const Text(
                    '新建储值小项',
                    style: TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onTap: () async {
                    final name = await showDialog<String>(
                      context: context,
                      builder: (c) {
                        final tc = TextEditingController(
                          text: _searchController.text.trim(),
                        );
                        return AlertDialog(
                          title: const Text('新建储值小项'),
                          content: TextField(
                            controller: tc,
                            decoration: const InputDecoration(
                              labelText: '名称',
                              hintText: '请输入储值小项名称',
                            ),
                            autofocus: true,
                            textCapitalization: TextCapitalization.none,
                            inputFormatters: [
                              LengthLimitingTextInputFormatter(50),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(c, tc.text.trim()),
                              child: const Text('确定'),
                            ),
                          ],
                        );
                      },
                    );
                    if (name != null && name.isNotEmpty) {
                      final newId = await widget.onCreateNew(name);
                      if (context.mounted && newId != null) {
                        setState(() => _selectedIds.add(newId));
                      }
                    }
                  },
                ),
                const Divider(),
              ],
              ...filtered.map((opt) {
                final selected = _selectedIds.contains(opt.id);
                final stock = balanceMap?[opt.id];
                final loadingCell = loadingRow;
                return ListTile(
                  leading: Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  title: Text(opt.name),
                  trailing: loadingCell
                      ? Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            '加载中',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        )
                      : stock != null
                      ? Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Badge(
                            label: Text(
                              '余$stock',
                              style: const TextStyle(fontSize: 11),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                          ),
                        )
                      : null,
                  onTap: () {
                    setState(() {
                      if (selected) {
                        _selectedIds.remove(opt.id);
                        widget.onRemove(opt.id);
                      } else {
                        _selectedIds.add(opt.id);
                        widget.onAdd(opt.id);
                      }
                    });
                  },
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? widget.options
        : widget.options
              .where((o) => o.name.toLowerCase().contains(query))
              .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollController) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '搜索储值小项',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                textInputAction: TextInputAction.search,
                autofocus: false,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: widget.inventoryBalancesListenable != null
                  ? ValueListenableBuilder<Map<int, int>?>(
                      valueListenable: widget.inventoryBalancesListenable!,
                      builder: (context, balanceMap, _) =>
                          _buildPickerScrollArea(
                            context,
                            scrollController,
                            filtered,
                            balanceMap,
                          ),
                    )
                  : _buildPickerScrollArea(
                      context,
                      scrollController,
                      filtered,
                      widget.remainingStockBySmallItemId,
                    ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('完成'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
