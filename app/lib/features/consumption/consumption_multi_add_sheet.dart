import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data_refresh.dart';
import '../../core/error_message.dart';
import '../../core/write_request_id.dart';
import '../storage/storage_model.dart';
import '../storage/storage_small_item_picker.dart';
import '../storage_options/storage_small_item_repository.dart';
import 'consumption_model.dart';
import 'consumption_repository.dart';

class ConsumptionMultiAddSheet extends StatefulWidget {
  const ConsumptionMultiAddSheet({
    super.key,
    required this.storage,
    required this.remainingCount,
  });

  final StorageRecordModel storage;
  final int remainingCount;

  @override
  State<ConsumptionMultiAddSheet> createState() =>
      _ConsumptionMultiAddSheetState();
}

class _ConsumptionDraft {
  _ConsumptionDraft({
    required this.date,
    required this.projectIds,
    this.remark = '',
    String? requestId,
  }) : requestId = requestId ?? newWriteRequestId();

  DateTime date;
  List<int> projectIds;
  String remark;
  final String requestId;
}

class _ConsumptionMultiAddSheetState extends State<ConsumptionMultiAddSheet> {
  final List<_ConsumptionDraft> _drafts = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initDrafts();
  }

  void _initDrafts() {
    final defaultProjectIds = widget.storage.storageSmallItemIds.isNotEmpty
        ? [widget.storage.storageSmallItemIds.first]
        : <int>[];
    _drafts.add(
      _ConsumptionDraft(date: DateTime.now(), projectIds: defaultProjectIds),
    );
  }

  void _addDraft() {
    if (_drafts.length >= widget.remainingCount) {
      final msg = '剩余消费次数不足，当前剩余 ${widget.remainingCount} 次';
      setState(() {
        _error = msg;
      });
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('无法新增消费'),
          content: Text(msg),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }
    final defaultProjectIds = widget.storage.storageSmallItemIds.isNotEmpty
        ? [widget.storage.storageSmallItemIds.first]
        : <int>[];
    setState(() {
      _drafts.add(
        _ConsumptionDraft(date: DateTime.now(), projectIds: defaultProjectIds),
      );
    });
  }

  void _removeDraft(int index) {
    if (_drafts.length <= 1) return;
    setState(() {
      _drafts.removeAt(index);
    });
  }

  Future<void> _saveAll() async {
    if (_loading) return;
    if (_drafts.isEmpty) return;

    final validDrafts = _drafts;
    if (validDrafts.length > widget.remainingCount) {
      final msg = '新增消费条数不能超过剩余次数（当前剩余 ${widget.remainingCount} 次）';
      setState(() {
        _error = msg;
      });
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('保存失败'),
          content: Text(msg),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }

    for (var i = 0; i < validDrafts.length; i++) {
      if (validDrafts[i].projectIds.isEmpty) {
        final msg = '请为第 ${i + 1} 条消费选择至少一个消费项目';
        setState(() {
          _error = msg;
        });
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('保存失败'),
            content: Text(msg),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
        return;
      }
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repo = context.read<ConsumptionRepository>();
      final storageId = widget.storage.id;
      final createdRecords = <ConsumptionRecordModel>[];

      for (final draft in validDrafts) {
        final projIds = draft.projectIds;
        final created = await repo.create(
          ConsumptionRecordModel(
            id: 0,
            code: '',
            consumptionDate: draft.date,
            storageRecordId: storageId,
            consumptionProjectId: projIds.isNotEmpty ? projIds.first : null,
            consumptionProjectIds: List<int>.from(projIds),
            remark: draft.remark.trim().isEmpty ? null : draft.remark.trim(),
            clientRequestId: draft.requestId,
          ),
        );
        createdRecords.add(created);
      }

      if (!mounted) return;
      context.read<DataRefreshNotifier>().invalidateStorageAndConsumption();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已新增 ${validDrafts.length} 条消费记录')),
      );
      Navigator.pop(context, createdRecords);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = toUserFriendlyError(e);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败：${toUserFriendlyError(e)}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final smallItemRepo = context.read<StorageSmallItemRepository>();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '批量新增消费',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.storage.customerName} · 剩余次数：${widget.remainingCount}',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  if (_error != null) ...[
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<StorageSmallItemOption>>(
                future: smallItemRepo.getAll(),
                builder: (context, snapshot) {
                  final allOptions = snapshot.data ?? [];
                  final validIds = widget.storage.storageSmallItemIds;
                  // 储值无小项时使用全量，否则仅限储值已有小项
                  final projectOptions = validIds.isEmpty
                      ? allOptions
                      : allOptions
                            .where((o) => validIds.contains(o.id))
                            .toList();

                  if (snapshot.connectionState == ConnectionState.waiting &&
                      allOptions.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: _drafts.length + 1,
                    itemBuilder: (context, index) {
                      if (index == _drafts.length) {
                        return Column(
                          children: [
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.add),
                                label: const Text('新增消费'),
                                onPressed: _loading ? null : _addDraft,
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                        );
                      }
                      return _buildDraftCard(
                        context,
                        index,
                        projectOptions,
                        validIds.isEmpty,
                      );
                    },
                  );
                },
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _loading ? null : _saveAll,
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('保存全部'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDraftCard(
    BuildContext context,
    int index,
    List<StorageSmallItemOption> projectOptions,
    bool allowCreate,
  ) {
    final draft = _drafts[index];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '消费 ${index + 1}',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (_drafts.length > 1)
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: '删除此消费',
                    onPressed: _loading ? null : () => _removeDraft(index),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('消费日期'),
              subtitle: Text(
                '${draft.date.year}-${draft.date.month.toString().padLeft(2, '0')}-${draft.date.day.toString().padLeft(2, '0')}',
              ),
              onTap: _loading
                  ? null
                  : () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: draft.date,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        locale: const Locale('zh', 'CN'),
                      );
                      if (d != null) {
                        setState(() {
                          draft.date = d;
                        });
                      }
                    },
            ),
            const SizedBox(height: 8),
            const Text('消费项目（可多选）'),
            const SizedBox(height: 4),
            StorageSmallItemPicker(
              options: projectOptions,
              selectedIds: draft.projectIds,
              onAdd: (id) {
                setState(() {
                  if (!draft.projectIds.contains(id)) {
                    draft.projectIds.add(id);
                  }
                });
              },
              onRemove: (id) {
                setState(() {
                  draft.projectIds.remove(id);
                });
              },
              onCreateNew: (name) async {
                final repo = context.read<StorageSmallItemRepository>();
                final opt = await repo.getOrCreate(name);
                return opt.id;
              },
              allowCreate: allowCreate,
              addButtonLabelWhenEmpty: '选择消费项目',
              addButtonLabelWhenNotEmpty: '修改 / 添加消费项目',
              subtleButton: true,
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: draft.remark,
              decoration: const InputDecoration(
                labelText: '备注',
                hintText: '可选',
              ),
              maxLines: 2,
              onChanged: (v) {
                draft.remark = v;
              },
            ),
          ],
        ),
      ),
    );
  }
}
