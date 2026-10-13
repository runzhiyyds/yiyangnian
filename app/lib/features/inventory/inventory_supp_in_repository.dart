import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/repository_read_cache.dart';

import 'inventory_models.dart';

class InventorySuppInRepository {
  InventorySuppInRepository(this._client, {RepositoryReadCache? readCache})
    : _readCache = readCache;

  final SupabaseClient _client;
  final RepositoryReadCache? _readCache;

  Future<List<T>> _read<T>(String key, Future<List<T>> Function() load) =>
      _readCache?.read<T>(key, load) ?? load();

  Future<List<InventorySuppInRecordModel>> getAll() =>
      _read('InventorySuppInRepository.getAll', () async {
        final res = await _client
            .from('inventory_supplementary_in_records')
            .select()
            .order('supplement_date', ascending: false)
            .order('occurred_at', ascending: false)
            .order('id', ascending: false);
        return (res as List)
            .map(
              (e) => InventorySuppInRecordModel.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList();
      });

  Future<List<InventorySuppInRecordModel>> getBySmallItemId(
    int storageSmallItemId,
  ) async {
    final res = await _client
        .from('inventory_supplementary_in_records')
        .select()
        .eq('storage_small_item_id', storageSmallItemId)
        .order('supplement_date', ascending: false)
        .order('occurred_at', ascending: false)
        .order('id', ascending: false);
    return (res as List)
        .map(
          (e) => InventorySuppInRecordModel.fromJson(
            Map<String, dynamic>.from(e as Map),
          ),
        )
        .toList();
  }

  Future<InventorySuppInRecordModel?> getById(int id) async {
    final res = await _client
        .from('inventory_supplementary_in_records')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (res == null) return null;
    return InventorySuppInRecordModel.fromJson(
      Map<String, dynamic>.from(res as Map),
    );
  }

  Future<InventorySuppInRecordModel> create(
    InventorySuppInRecordModel record,
  ) async {
    try {
      final res = await _client
          .from('inventory_supplementary_in_records')
          .insert(record.toJson())
          .select()
          .single();
      return InventorySuppInRecordModel.fromJson(
        Map<String, dynamic>.from(res as Map),
      );
    } finally {
      _readCache?.clear();
    }
  }

  Future<InventorySuppInRecordModel> update(
    InventorySuppInRecordModel record,
  ) async {
    try {
      final res = await _client
          .from('inventory_supplementary_in_records')
          .update(record.toJson())
          .eq('id', record.id)
          .select()
          .single();
      return InventorySuppInRecordModel.fromJson(
        Map<String, dynamic>.from(res as Map),
      );
    } finally {
      _readCache?.clear();
    }
  }

  Future<InventorySuppInRecordModel> voidRecord(
    int id, {
    required String reason,
  }) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) throw StateError('当前登录已失效，请重新登录');
      final res = await _client
          .from('inventory_supplementary_in_records')
          .update({
            'voided_at': DateTime.now().toUtc().toIso8601String(),
            'voided_by': userId,
            'void_reason': reason.trim(),
          })
          .eq('id', id)
          .isFilter('voided_at', null)
          .select()
          .single();
      return InventorySuppInRecordModel.fromJson(
        Map<String, dynamic>.from(res as Map),
      );
    } finally {
      _readCache?.clear();
    }
  }
}
