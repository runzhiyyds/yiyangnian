import 'package:supabase_flutter/supabase_flutter.dart';

import 'consumption_model.dart';

/// 消费数据仓库抽象，便于单测注入 Mock/Fake。
abstract class ConsumptionRepositoryBase {
  Future<String> generateConsumptionCode();
  Future<List<ConsumptionRecordModel>> getByDateRange(DateTime start, DateTime end);
  Future<List<ConsumptionRecordModel>> getByStorage(int storageRecordId);
  /// 批量按储值 ID 拉取消费记录（首页树用，避免按储值逐条请求）
  Future<List<ConsumptionRecordModel>> getByStorageIds(Iterable<int> storageRecordIds);
  Future<ConsumptionRecordModel?> getById(int id);
  Future<int> getConsumedCount(int storageRecordId);
  Future<ConsumptionRecordModel> create(ConsumptionRecordModel record);
  Future<ConsumptionRecordModel> update(ConsumptionRecordModel record);
  Future<void> delete(int id);
}

class ConsumptionRepository implements ConsumptionRepositoryBase {
  ConsumptionRepository(this._client);

  final SupabaseClient _client;

  Future<String> generateConsumptionCode() async {
    final res = await _client.rpc('generate_consumption_code');
    return res as String;
  }

  /// 按消费日期范围查询（仅比较日期，用于分析看板）
  Future<List<ConsumptionRecordModel>> getByDateRange(DateTime start, DateTime end) async {
    final startStr = '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
    final endStr = '${end.year}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')}';
    final res = await _client
        .from('consumption_records')
        .select()
        .gte('consumption_date', startStr)
        .lte('consumption_date', endStr)
        .order('consumption_date', ascending: true);
    return (res as List)
        .map((e) =>
            ConsumptionRecordModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<ConsumptionRecordModel>> getByStorage(int storageRecordId) async {
    final res = await _client
        .from('consumption_records')
        .select()
        .eq('storage_record_id', storageRecordId)
        .order('consumption_date', ascending: false);
    return (res as List)
        .map((e) =>
            ConsumptionRecordModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static const _inChunkSize = 120;

  Future<List<ConsumptionRecordModel>> getByStorageIds(Iterable<int> storageRecordIds) async {
    final ids = storageRecordIds.toSet().toList();
    if (ids.isEmpty) return [];
    final all = <ConsumptionRecordModel>[];
    for (var i = 0; i < ids.length; i += _inChunkSize) {
      final end = (i + _inChunkSize > ids.length) ? ids.length : i + _inChunkSize;
      final chunk = ids.sublist(i, end);
      final res = await _client
          .from('consumption_records')
          .select()
          .inFilter('storage_record_id', chunk)
          .order('consumption_date', ascending: false);
      all.addAll(
        (res as List)
            .map((e) =>
                ConsumptionRecordModel.fromJson(Map<String, dynamic>.from(e as Map))),
      );
    }
    return all;
  }

  Future<ConsumptionRecordModel?> getById(int id) async {
    final res = await _client
        .from('consumption_records')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (res == null) return null;
    return ConsumptionRecordModel.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<int> getConsumedCount(int storageRecordId) async {
    final res = await _client
        .from('consumption_records')
        .select()
        .eq('storage_record_id', storageRecordId);
    return (res as List).length;
  }

  Future<ConsumptionRecordModel> create(ConsumptionRecordModel record) async {
    final code = await generateConsumptionCode();
    final data = record.toJson();
    data['code'] = code;
    final res = await _client
        .from('consumption_records')
        .insert(data)
        .select()
        .single();
    return ConsumptionRecordModel.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<ConsumptionRecordModel> update(ConsumptionRecordModel record) async {
    final res = await _client
        .from('consumption_records')
        .update(record.toJson())
        .eq('id', record.id)
        .select()
        .single();
    return ConsumptionRecordModel.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<void> delete(int id) async {
    await _client.from('consumption_records').delete().eq('id', id);
  }
}
