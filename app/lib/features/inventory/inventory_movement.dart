import 'inventory_models.dart';
import '../storage/storage_model.dart';

enum InventoryMovementSource { purchase, supplementaryIn, outbound }

enum InventoryMovementFilter { all, inbound, outbound }

class InventoryMovement {
  const InventoryMovement({
    required this.source,
    required this.sourceId,
    required this.smallItemId,
    required this.occurredAt,
    required this.delta,
    required this.title,
    required this.balanceAfter,
    this.remark,
    this.sourceStorageRecordId,
    this.sourceStorageCode,
    this.sourceCustomerName,
    this.isAutomaticOutbound = false,
    this.isEstimatedTime = false,
    this.isReversal = false,
    this.originalVoidedAt,
    this.voidReason,
  });

  final InventoryMovementSource source;
  final int sourceId;
  final int smallItemId;
  final DateTime occurredAt;
  final int delta;
  final String title;
  final int balanceAfter;
  final String? remark;
  final int? sourceStorageRecordId;
  final String? sourceStorageCode;
  final String? sourceCustomerName;
  final bool isAutomaticOutbound;
  final bool isEstimatedTime;
  final bool isReversal;
  final DateTime? originalVoidedAt;
  final String? voidReason;

  bool get isInbound => delta > 0;
  bool get originalIsVoided => !isReversal && originalVoidedAt != null;

  String get route => switch (source) {
    InventoryMovementSource.purchase => '/inventory/purchase/$sourceId',
    InventoryMovementSource.supplementaryIn => '/inventory/supp-in/$sourceId',
    InventoryMovementSource.outbound => '/inventory/supp-out/$sourceId',
  };

  InventoryMovement copyWithBalance(int value) => InventoryMovement(
    source: source,
    sourceId: sourceId,
    smallItemId: smallItemId,
    occurredAt: occurredAt,
    delta: delta,
    title: title,
    balanceAfter: value,
    remark: remark,
    sourceStorageRecordId: sourceStorageRecordId,
    sourceStorageCode: sourceStorageCode,
    sourceCustomerName: sourceCustomerName,
    isAutomaticOutbound: isAutomaticOutbound,
    isEstimatedTime: isEstimatedTime,
    isReversal: isReversal,
    originalVoidedAt: originalVoidedAt,
    voidReason: voidReason,
  );
}

class InventoryMovementLedger {
  InventoryMovementLedger._();

  static List<InventoryMovement> forItem({
    required int smallItemId,
    required List<InventoryPurchaseRecordModel> purchases,
    required List<InventorySuppInRecordModel> supplementaryIn,
    required List<InventoryConsumptionRecordModel> outbound,
    Map<int, StorageRecordModel> sourceStorages = const {},
  }) {
    final movements = <InventoryMovement>[];

    for (final purchase in purchases) {
      for (
        var index = 0;
        index < purchase.storageSmallItemIds.length &&
            index < purchase.quantities.length;
        index++
      ) {
        if (purchase.storageSmallItemIds[index] != smallItemId) continue;
        final quantity = purchase.quantities[index];
        final occurredAt =
            purchase.occurredAt ??
            _legacyTime(purchase.purchaseDate, const Duration(hours: 9));
        movements.add(
          InventoryMovement(
            source: InventoryMovementSource.purchase,
            sourceId: purchase.id,
            smallItemId: smallItemId,
            occurredAt: occurredAt,
            delta: quantity,
            title: '进货入库',
            balanceAfter: 0,
            remark: purchase.remark,
            isEstimatedTime:
                purchase.occurredAt == null || purchase.occurredAtEstimated,
            originalVoidedAt: purchase.voidedAt,
            voidReason: purchase.voidReason,
          ),
        );
        if (purchase.voidedAt != null) {
          movements.add(
            InventoryMovement(
              source: InventoryMovementSource.purchase,
              sourceId: purchase.id,
              smallItemId: smallItemId,
              occurredAt: purchase.voidedAt!,
              delta: -quantity,
              title: '撤销进货入库',
              balanceAfter: 0,
              isReversal: true,
              voidReason: purchase.voidReason,
            ),
          );
        }
      }
    }

    for (final record in supplementaryIn) {
      if (record.storageSmallItemId != smallItemId) continue;
      final occurredAt =
          record.occurredAt ??
          _legacyTime(record.supplementDate, const Duration(hours: 12));
      movements.add(
        InventoryMovement(
          source: InventoryMovementSource.supplementaryIn,
          sourceId: record.id,
          smallItemId: smallItemId,
          occurredAt: occurredAt,
          delta: record.quantity,
          title: '补充入库',
          balanceAfter: 0,
          remark: record.remark,
          isEstimatedTime:
              record.occurredAt == null || record.occurredAtEstimated,
          originalVoidedAt: record.voidedAt,
          voidReason: record.voidReason,
        ),
      );
      if (record.voidedAt != null) {
        movements.add(
          InventoryMovement(
            source: InventoryMovementSource.supplementaryIn,
            sourceId: record.id,
            smallItemId: smallItemId,
            occurredAt: record.voidedAt!,
            delta: -record.quantity,
            title: '撤销补充入库',
            balanceAfter: 0,
            isReversal: true,
            voidReason: record.voidReason,
          ),
        );
      }
    }

    for (final record in outbound) {
      if (record.storageSmallItemId != smallItemId) continue;
      final occurredAt =
          record.occurredAt ??
          _legacyTime(record.consumptionDate, const Duration(hours: 18));
      final isAutomaticOutbound =
          record.sourceStorageRecordId != null ||
          (record.remark ?? '').trim().startsWith('自动出库');
      final sourceStorage = record.sourceStorageRecordId == null
          ? null
          : sourceStorages[record.sourceStorageRecordId!];
      final title = isAutomaticOutbound ? '储值自动出库' : '手工出库';
      movements.add(
        InventoryMovement(
          source: InventoryMovementSource.outbound,
          sourceId: record.id,
          smallItemId: smallItemId,
          occurredAt: occurredAt,
          delta: -record.quantity,
          title: title,
          balanceAfter: 0,
          remark: record.remark,
          sourceStorageRecordId: record.sourceStorageRecordId,
          sourceStorageCode: sourceStorage?.code,
          sourceCustomerName: sourceStorage?.customerName,
          isAutomaticOutbound: isAutomaticOutbound,
          isEstimatedTime:
              record.occurredAt == null || record.occurredAtEstimated,
          originalVoidedAt: record.voidedAt,
          voidReason: record.voidReason,
        ),
      );
      if (record.voidedAt != null) {
        movements.add(
          InventoryMovement(
            source: InventoryMovementSource.outbound,
            sourceId: record.id,
            smallItemId: smallItemId,
            occurredAt: record.voidedAt!,
            delta: record.quantity,
            title: isAutomaticOutbound ? '撤销储值自动出库' : '撤销手工出库',
            balanceAfter: 0,
            sourceStorageRecordId: record.sourceStorageRecordId,
            sourceStorageCode: sourceStorage?.code,
            sourceCustomerName: sourceStorage?.customerName,
            isAutomaticOutbound: isAutomaticOutbound,
            isReversal: true,
            voidReason: record.voidReason,
          ),
        );
      }
    }

    movements.sort(_ascendingComparator);
    var balance = 0;
    final withBalance = <InventoryMovement>[];
    for (final movement in movements) {
      balance += movement.delta;
      withBalance.add(movement.copyWithBalance(balance));
    }
    return withBalance.reversed.toList(growable: false);
  }

  static int _ascendingComparator(
    InventoryMovement left,
    InventoryMovement right,
  ) {
    final time = left.occurredAt.compareTo(right.occurredAt);
    if (time != 0) return time;
    final source = _sourcePriority(left).compareTo(_sourcePriority(right));
    if (source != 0) return source;
    return left.sourceId.compareTo(right.sourceId);
  }

  static int _sourcePriority(InventoryMovement movement) {
    if (movement.isReversal) return 3;
    return switch (movement.source) {
      InventoryMovementSource.purchase => 0,
      InventoryMovementSource.supplementaryIn => 1,
      InventoryMovementSource.outbound => 2,
    };
  }

  static DateTime _legacyTime(DateTime date, Duration time) =>
      DateTime(date.year, date.month, date.day).add(time);
}
