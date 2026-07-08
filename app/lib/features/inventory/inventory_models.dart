/// 进货记录模型（inventory_purchase_records）
class InventoryPurchaseRecordModel {
  final int id;
  final String code;
  final DateTime purchaseDate;
  final List<String> storageBigItems;
  final List<int> storageSmallItemIds;
  final List<int> quantities;
  final double totalAmount;
  final String? remark;
  final DateTime? createdAt;

  InventoryPurchaseRecordModel({
    required this.id,
    required this.code,
    required this.purchaseDate,
    required this.storageBigItems,
    required this.storageSmallItemIds,
    required this.quantities,
    this.totalAmount = 0,
    this.remark,
    this.createdAt,
  });

  factory InventoryPurchaseRecordModel.fromJson(Map<String, dynamic> json) {
    List<String> bigItems = [];
    if (json['storage_big_items'] != null) {
      final list = json['storage_big_items'] as List<dynamic>?;
      if (list != null) {
        bigItems = list.map((e) => e.toString()).toList();
      }
    }
    List<int> smallIds = [];
    if (json['storage_small_item_ids'] != null) {
      final list = json['storage_small_item_ids'] as List<dynamic>?;
      if (list != null) {
        smallIds = list
            .map((e) => (e is int) ? e : int.tryParse(e.toString()) ?? 0)
            .toList();
      }
    }
    List<int> qty = [];
    if (json['quantities'] != null) {
      final list = json['quantities'] as List<dynamic>?;
      if (list != null) {
        qty = list
            .map((e) => (e is int) ? e : int.tryParse(e.toString()) ?? 0)
            .toList();
      }
    }
    DateTime purchaseDate = DateTime.now();
    if (json['purchase_date'] != null) {
      purchaseDate = DateTime.parse(json['purchase_date'] as String);
    }
    DateTime? createdAt;
    if (json['created_at'] != null) {
      createdAt = DateTime.parse(json['created_at'] as String);
    }
    return InventoryPurchaseRecordModel(
      id: json['id'] as int,
      code: json['code'] as String,
      purchaseDate: purchaseDate,
      storageBigItems: bigItems,
      storageSmallItemIds: smallIds,
      quantities: qty,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0,
      remark: json['remark'] as String?,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'purchase_date': purchaseDate.toIso8601String().split('T').first,
      'storage_big_items': storageBigItems,
      'storage_small_item_ids': storageSmallItemIds,
      'quantities': quantities,
      'total_amount': totalAmount,
      if (remark != null && remark!.isNotEmpty) 'remark': remark,
    };
  }
}

/// 库存出库记录模型（inventory_consumption_records）
class InventoryConsumptionRecordModel {
  final int id;
  final DateTime consumptionDate;
  final int storageSmallItemId;
  final int quantity;
  final String? remark;
  /// 由新建储值自动出库时关联的储值记录 ID（需 DB 迁移列 source_storage_record_id）
  final int? sourceStorageRecordId;
  final DateTime? createdAt;

  InventoryConsumptionRecordModel({
    required this.id,
    required this.consumptionDate,
    required this.storageSmallItemId,
    required this.quantity,
    this.remark,
    this.sourceStorageRecordId,
    this.createdAt,
  });

  factory InventoryConsumptionRecordModel.fromJson(Map<String, dynamic> json) {
    DateTime consumptionDate = DateTime.now();
    if (json['consumption_date'] != null) {
      consumptionDate = DateTime.parse(json['consumption_date'] as String);
    }
    DateTime? createdAt;
    if (json['created_at'] != null) {
      createdAt = DateTime.parse(json['created_at'] as String);
    }
    return InventoryConsumptionRecordModel(
      id: json['id'] as int,
      consumptionDate: consumptionDate,
      storageSmallItemId: json['storage_small_item_id'] as int,
      quantity: json['quantity'] as int,
      remark: json['remark'] as String?,
      sourceStorageRecordId: json['source_storage_record_id'] as int?,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'consumption_date': consumptionDate.toIso8601String().split('T').first,
      'storage_small_item_id': storageSmallItemId,
      'quantity': quantity,
      if (remark != null && remark!.isNotEmpty) 'remark': remark,
      if (sourceStorageRecordId != null) 'source_storage_record_id': sourceStorageRecordId,
    };
  }
}

/// 补充入库记录模型（inventory_supplementary_in_records）
class InventorySuppInRecordModel {
  final int id;
  final DateTime supplementDate;
  final int storageSmallItemId;
  final int quantity;
  final String? remark;
  final DateTime? createdAt;

  InventorySuppInRecordModel({
    required this.id,
    required this.supplementDate,
    required this.storageSmallItemId,
    required this.quantity,
    this.remark,
    this.createdAt,
  });

  factory InventorySuppInRecordModel.fromJson(Map<String, dynamic> json) {
    DateTime supplementDate = DateTime.now();
    if (json['supplement_date'] != null) {
      supplementDate = DateTime.parse(json['supplement_date'] as String);
    }
    DateTime? createdAt;
    if (json['created_at'] != null) {
      createdAt = DateTime.parse(json['created_at'] as String);
    }
    return InventorySuppInRecordModel(
      id: json['id'] as int,
      supplementDate: supplementDate,
      storageSmallItemId: json['storage_small_item_id'] as int,
      quantity: json['quantity'] as int,
      remark: json['remark'] as String?,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'supplement_date': supplementDate.toIso8601String().split('T').first,
      'storage_small_item_id': storageSmallItemId,
      'quantity': quantity,
      if (remark != null && remark!.isNotEmpty) 'remark': remark,
    };
  }
}
