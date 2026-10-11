import 'package:flutter/material.dart';

import '../../storage/storage_model.dart';

class InventoryLinkedStorages extends StatelessWidget {
  const InventoryLinkedStorages({
    super.key,
    required this.storages,
    required this.onTap,
    this.maxVisible,
    this.onViewAll,
  });

  final List<StorageRecordModel> storages;
  final ValueChanged<StorageRecordModel> onTap;
  final int? maxVisible;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    final visible = maxVisible == null
        ? storages
        : storages.take(maxVisible!).toList(growable: false);
    final hasMore = visible.length < storages.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '关联储值',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              '${storages.length}条',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '包含当前小项的客户储值记录',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
        const SizedBox(height: 8),
        if (storages.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '暂无关联储值',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          )
        else
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (var index = 0; index < visible.length; index++) ...[
                  _StorageTile(
                    storage: visible[index],
                    onTap: () => onTap(visible[index]),
                  ),
                  if (index != visible.length - 1)
                    const Divider(height: 1, indent: 16, endIndent: 16),
                ],
                if (hasMore && onViewAll != null) ...[
                  const Divider(height: 1),
                  TextButton.icon(
                    onPressed: onViewAll,
                    icon: const Icon(Icons.list_alt_outlined, size: 18),
                    label: Text('查看全部 ${storages.length} 条储值'),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _StorageTile extends StatelessWidget {
  const _StorageTile({required this.storage, required this.onTap});

  final StorageRecordModel storage;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = storage.storageDate;
    final dateText =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final code = storage.code.trim().isEmpty ? '储值记录' : storage.code.trim();
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Icon(
          Icons.account_balance_wallet_outlined,
          color: Theme.of(context).colorScheme.primary,
          size: 20,
        ),
      ),
      title: Text(
        storage.customerName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '$code · $dateText\n¥${storage.amount.toStringAsFixed(0)} · ${storage.totalCount}次',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
