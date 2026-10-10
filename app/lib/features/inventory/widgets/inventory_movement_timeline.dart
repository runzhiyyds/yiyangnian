import 'package:flutter/material.dart';

import '../inventory_movement.dart';

class InventoryMovementTimeline extends StatelessWidget {
  const InventoryMovementTimeline({
    super.key,
    required this.movements,
    required this.onTap,
    this.compact = false,
  });

  final List<InventoryMovement> movements;
  final ValueChanged<InventoryMovement> onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (movements.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: Text(
            '暂无库存变化记录',
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ),
      );
    }

    return Column(
      children: [
        for (var index = 0; index < movements.length; index++)
          _MovementRow(
            movement: movements[index],
            isLast: index == movements.length - 1,
            compact: compact,
            onTap: () => onTap(movements[index]),
          ),
      ],
    );
  }
}

class _MovementRow extends StatelessWidget {
  const _MovementRow({
    required this.movement,
    required this.isLast,
    required this.compact,
    required this.onTap,
  });

  final InventoryMovement movement;
  final bool isLast;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final positive = movement.delta > 0;
    final color = movement.isReversal
        ? colorScheme.tertiary
        : positive
        ? Colors.green.shade700
        : Colors.orange.shade800;
    final date = _formatDate(movement.occurredAt);
    final time = movement.isEstimatedTime
        ? '历史记录，按规则排序'
        : _formatTime(movement.occurredAt);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.only(top: 22),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: colorScheme.surface, width: 2),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: colorScheme.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Card(
              margin: EdgeInsets.only(bottom: compact ? 8 : 12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onTap,
                child: Padding(
                  padding: EdgeInsets.all(compact ? 10 : 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  movement.title,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    decoration: movement.originalIsVoided
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$date · $time',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: colorScheme.outline),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${positive ? '+' : ''}${movement.delta}件',
                            style: TextStyle(
                              color: color,
                              fontSize: compact ? 15 : 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right, size: 20),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '变更后库存：${movement.balanceAfter}件',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (movement.originalIsVoided) ...[
                        const SizedBox(height: 6),
                        Text(
                          '该记录已撤销，撤销操作在时间线中单独留痕',
                          style: TextStyle(
                            color: colorScheme.error,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      if ((movement.voidReason ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${movement.isReversal || movement.originalIsVoided ? '撤销原因' : '备注'}：${movement.voidReason!.trim()}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ] else if ((movement.remark ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          movement.remark!.trim(),
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: compact ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  String _formatTime(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
