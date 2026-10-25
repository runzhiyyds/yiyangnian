import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/repository_read_cache.dart';

import 'inventory_models.dart';

/// 库存出库记录仓库（inventory_consumption_records，与客户消费 consumption_records 隔离）
class InventoryConsumptionRepository {
  InventoryConsumptionRepository(this._client, {RepositoryReadCache? readCache})
    : _readCache = readCache;

  final SupabaseClient _client;
  final RepositoryReadCache? _readCache;

  Future<List<T>> _read<T>(String key, Future<List<T>> Function() load) =>
      _readCache?.read<T>(key, load) ?? load();

  Future<List<InventoryConsumptionRecordModel>> getAll() =>
      _read('InventoryConsumptionRepository.getAll', () async {
        final res = await _client
            .from('inventory_consumption_records')
            .select()
            .order('consumption_date', ascending: false)
            .order('occurred_at', ascending: false)
            .order('id', ascending: false);
        return (res as List)
            .map(
              (e) => InventoryConsumptionRecordModel.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList();
      });

  Future<List<InventoryConsumptionRecordModel>> getBySmallItemId(
    int storageSmallItemId,
  ) async {
    final res = await _client
        .from('inventory_consumption_records')
        .select()
        .eq('storage_small_item_id', storageSmallItemId)
        .order('consumption_date', ascending: false)
        .order('occurred_at', ascending: false)
        .order('id', ascending: false);
    return (res as List)
        .map(
          (e) => InventoryConsumptionRecordModel.fromJson(
            Map<String, dynamic>.from(e as Map),
          ),
        )
        .toList();
  }

  Future<InventoryConsumptionRecordModel?> getById(int id) async {
    final res = await _client
        .from('inventory_consumption_records')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (res == null) return null;
    return InventoryConsumptionRecordModel.fromJson(
      Map<String, dynamic>.from(res as Map),
    );
  }

  Future<InventoryConsumptionRecordModel> create(
    InventoryConsumptionRecordModel record,
  ) async {
    try {
      final table = _client.from('inventory_consumption_records');
      final data = record.toJson();
      final res =
          await (record.clientRequestId == null
                  ? table.insert(data)
                  : table.upsert(
                      data,
                      onConflict: 'owner_id,client_request_id',
                    ))
              .select()
              .single();
      return InventoryConsumptionRecordModel.fromJson(
        Map<String, dynamic>.from(res as Map),
      );
    } finally {
      _readCache?.clear();
    }
  }

  /// 批量插入（新建储值多小项出库时一次往返，避免逐条 await）
  Future<List<InventoryConsumptionRecordModel>> createBatch(
    List<InventoryConsumptionRecordModel> records,
  ) async {
    try {
      if (records.isEmpty) return [];
      final rows = records.map((r) => r.toJson()).toList();
      final hasRequestIds = records.every(
        (record) => record.clientRequestId != null,
      );
      final table = _client.from('inventory_consumption_records');
      final res =
          await (hasRequestIds
                  ? table.upsert(rows, onConflict: 'owner_id,client_request_id')
                  : table.insert(rows))
              .select();
      return (res as List)
          .map(
            (e) => InventoryConsumptionRecordModel.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
    } finally {
      _readCache?.clear();
    }
  }

  Future<InventoryConsumptionRecordModel> update(
    InventoryConsumptionRecordModel record,
  ) async {
    try {
      final res = await _client
          .from('inventory_consumption_records')
          .update(record.toJson())
          .eq('id', record.id)
          .select()
          .single();
      return InventoryConsumptionRecordModel.fromJson(
        Map<String, dynamic>.from(res as Map),
      );
    } finally {
      _readCache?.clear();
    }
  }

  Future<InventoryConsumptionRecordModel> voidRecord(
    int id, {
    required String reason,
  }) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) throw StateError('当前登录已失效，请重新登录');
      final res = await _client
          .from('inventory_consumption_records')
          .update({
            'voided_at': DateTime.now().toUtc().toIso8601String(),
            'voided_by': userId,
            'void_reason': reason.trim(),
          })
          .eq('id', id)
          .isFilter('voided_at', null)
          .select()
          .single();
      return InventoryConsumptionRecordModel.fromJson(
        Map<String, dynamic>.from(res as Map),
      );
    } finally {
      _readCache?.clear();
    }
  }
}
