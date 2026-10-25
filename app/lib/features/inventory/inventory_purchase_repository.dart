import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/repository_read_cache.dart';

import 'inventory_models.dart';

class InventoryPurchaseRepository {
  InventoryPurchaseRepository(this._client, {RepositoryReadCache? readCache})
    : _readCache = readCache;

  final SupabaseClient _client;
  final RepositoryReadCache? _readCache;

  Future<List<T>> _read<T>(String key, Future<List<T>> Function() load) =>
      _readCache?.read<T>(key, load) ?? load();

  Future<String> generatePurchaseCode() async {
    final res = await _client.rpc('generate_inventory_purchase_code');
    return res as String;
  }

  Future<List<InventoryPurchaseRecordModel>> getAll() =>
      _read('InventoryPurchaseRepository.getAll', () async {
        final res = await _client
            .from('inventory_purchase_records')
            .select()
            .order('purchase_date', ascending: false)
            .order('occurred_at', ascending: false)
            .order('id', ascending: false);
        return (res as List)
            .map(
              (e) => InventoryPurchaseRecordModel.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList();
      });

  /// 按进货日期（含首尾日期）查询进货单，供周期经营分析使用。
  Future<List<InventoryPurchaseRecordModel>> getByDateRange(
    DateTime start,
    DateTime end,
  ) => _read(
    'InventoryPurchaseRepository.getByDateRange:${start.year}-${start.month}-${start.day}:${end.year}-${end.month}-${end.day}',
    () async {
      String dateOnly(DateTime date) =>
          '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';

      final res = await _client
          .from('inventory_purchase_records')
          .select()
          .gte('purchase_date', dateOnly(start))
          .lte('purchase_date', dateOnly(end))
          .order('purchase_date', ascending: false)
          .order('occurred_at', ascending: false)
          .order('id', ascending: false);
      return (res as List)
          .map(
            (e) => InventoryPurchaseRecordModel.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
    },
  );

  Future<InventoryPurchaseRecordModel?> getById(int id) async {
    final res = await _client
        .from('inventory_purchase_records')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (res == null) return null;
    return InventoryPurchaseRecordModel.fromJson(
      Map<String, dynamic>.from(res as Map),
    );
  }

  Future<InventoryPurchaseRecordModel> create(
    InventoryPurchaseRecordModel record,
  ) async {
    try {
      final owner = _client.auth.currentUser?.id;
      final code = await generatePurchaseCode();
      if (owner == null || _client.auth.currentUser?.id != owner) {
        throw StateError('登录账号已变化，请重新打开页面');
      }
      final data = record.toJson();
      data['code'] = code;
      final table = _client.from('inventory_purchase_records');
      final res =
          await (record.clientRequestId == null
                  ? table.insert(data)
                  : table.upsert(
                      data,
                      onConflict: 'owner_id,client_request_id',
                    ))
              .select()
              .single();
      return InventoryPurchaseRecordModel.fromJson(
        Map<String, dynamic>.from(res as Map),
      );
    } finally {
      _readCache?.clear();
    }
  }

  Future<InventoryPurchaseRecordModel> update(
    InventoryPurchaseRecordModel record,
  ) async {
    try {
      final res = await _client
          .from('inventory_purchase_records')
          .update(record.toJson())
          .eq('id', record.id)
          .select()
          .single();
      return InventoryPurchaseRecordModel.fromJson(
        Map<String, dynamic>.from(res as Map),
      );
    } finally {
      _readCache?.clear();
    }
  }

  Future<InventoryPurchaseRecordModel> voidRecord(
    int id, {
    required String reason,
  }) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) throw StateError('当前登录已失效，请重新登录');
      final res = await _client
          .from('inventory_purchase_records')
          .update({
            'voided_at': DateTime.now().toUtc().toIso8601String(),
            'voided_by': userId,
            'void_reason': reason.trim(),
          })
          .eq('id', id)
          .isFilter('voided_at', null)
          .select()
          .single();
      return InventoryPurchaseRecordModel.fromJson(
        Map<String, dynamic>.from(res as Map),
      );
    } finally {
      _readCache?.clear();
    }
  }
}
