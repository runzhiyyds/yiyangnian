import 'package:supabase_flutter/supabase_flutter.dart';

import 'storage_model.dart';

/// 储值数据仓库抽象，便于单测注入 Mock/Fake。
abstract class StorageRepositoryBase {
  Future<String> generateStorageCode();
  Future<List<StorageRecordModel>> getAll();
  Future<List<StorageRecordModel>> getByCustomer(String customerName);
  Future<List<StorageRecordModel>> getByStorageDateRange(DateTime start, DateTime end);
  Future<StorageRecordModel?> getById(int id);
  Future<int> getRemainingCount(int storageRecordId);
  Future<StorageRecordModel> create(StorageRecordModel record);
  Future<StorageRecordModel> update(StorageRecordModel record);
  Future<void> delete(int id);
  Future<void> deleteCascade(int id);
}

class StorageRepository implements StorageRepositoryBase {
  StorageRepository(this._client);

  final SupabaseClient _client;

  Future<String> generateStorageCode() async {
    final res = await _client.rpc('generate_storage_code');
    return res as String;
  }

  Future<List<StorageRecordModel>> getAll() async {
    final res = await _client
        .from('storage_records')
        .select()
        .order('storage_date', ascending: false);
    return (res as List)
        .map((e) => StorageRecordModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<StorageRecordModel>> getByCustomer(String customerName) async {
    final res = await _client
        .from('storage_records')
        .select()
        .eq('customer_name', customerName)
        .order('storage_date', ascending: false);
    return (res as List)
        .map((e) => StorageRecordModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// 储值时间在 [start]～[end]（含）内的储值记录，仅比较日期部分
  Future<List<StorageRecordModel>> getByStorageDateRange(DateTime start, DateTime end) async {
    final startDate = DateTime(start.year, start.month, start.day);
    final endDate = DateTime(end.year, end.month, end.day);
    final startStr = '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}';
    final endStr = '${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}';
    final res = await _client
        .from('storage_records')
        .select()
        .gte('storage_date', startStr)
        .lte('storage_date', endStr)
        .order('storage_date', ascending: false);
    return (res as List)
        .map((e) => StorageRecordModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<StorageRecordModel?> getById(int id) async {
    final res = await _client
        .from('storage_records')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (res == null) return null;
    return StorageRecordModel.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<int> getRemainingCount(int storageRecordId) async {
    final storage = await getById(storageRecordId);
    if (storage == null) return 0;
    final consumed = await _client
        .from('consumption_records')
        .select()
        .eq('storage_record_id', storageRecordId);
    return storage.totalCount - (consumed as List).length;
  }

  Future<StorageRecordModel> create(StorageRecordModel record) async {
    final code = await generateStorageCode();
    final data = record.toJson();
    data['code'] = code;
    final res = await _client
        .from('storage_records')
        .insert(data)
        .select()
        .single();
    return StorageRecordModel.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<StorageRecordModel> update(StorageRecordModel record) async {
    final res = await _client
        .from('storage_records')
        .update(record.toJson())
        .eq('id', record.id)
        .select()
        .single();
    return StorageRecordModel.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<void> delete(int id) async {
    await _client.from('storage_records').delete().eq('id', id);
  }

  /// 级联删除：先删该储值下所有消费记录，再删储值
  Future<void> deleteCascade(int id) async {
    await _client.from('consumption_records').delete().eq('storage_record_id', id);
    await _client.from('storage_records').delete().eq('id', id);
  }
}
