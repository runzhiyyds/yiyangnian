class StorageRecordModel {
  final int id;
  final String code;
  final String customerName;
  final List<String> storageBigItems;
  final List<int> storageSmallItemIds;
  final double amount;
  final int totalCount;
  final DateTime storageDate;
  final String? remark;
  final DateTime? createdAt;

  StorageRecordModel({
    required this.id,
    required this.code,
    required this.customerName,
    required this.storageBigItems,
    required this.storageSmallItemIds,
    required this.amount,
    required this.totalCount,
    required this.storageDate,
    this.remark,
    this.createdAt,
  });

  factory StorageRecordModel.fromJson(Map<String, dynamic> json) {
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
        smallIds = list.map((e) => (e is int) ? e : int.tryParse(e.toString()) ?? 0).where((e) => e > 0).toList();
      }
    }
    DateTime storageDate = DateTime.now();
    if (json['storage_date'] != null) {
      storageDate = DateTime.parse(json['storage_date'] as String);
    }
    DateTime? createdAt;
    if (json['created_at'] != null) {
      createdAt = DateTime.parse(json['created_at'] as String);
    }
    final remark = json['remark'] as String?;
    return StorageRecordModel(
      id: json['id'] as int,
      code: json['code'] as String,
      customerName: json['customer_name'] as String,
      storageBigItems: bigItems,
      storageSmallItemIds: smallIds,
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      totalCount: json['total_count'] as int? ?? 0,
      storageDate: storageDate,
      remark: remark != null && remark.isNotEmpty ? remark : null,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    final r = remark;
    return {
      'code': code,
      'customer_name': customerName,
      'storage_big_items': storageBigItems,
      'storage_small_item_ids': storageSmallItemIds,
      'amount': amount,
      'total_count': totalCount,
      'storage_date': storageDate.toIso8601String().split('T').first,
      if (r != null && r.isNotEmpty) 'remark': r,
    };
  }
}
