import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/repository_read_cache.dart';

import 'storage_model.dart';

/// 储值数据仓库抽象，便于单测注入 Mock/Fake。
abstract class StorageRepositoryBase {
  Future<String> generateStorageCode();
  Future<List<StorageRecordModel>> getAll();
  Future<List<StorageRecordModel>> getByCustomer(String customerName);
  Future<List<StorageRecordModel>> getByStorageDateRange(
    DateTime start,
    DateTime end,
  );
  Future<StorageRecordModel?> getById(int id);
  Future<List<StorageRecordModel>> getByIds(Iterable<int> ids);
  Future<int> getRemainingCount(int storageRecordId);
  Future<StorageRecordModel> create(StorageRecordModel record);
  Future<StorageRecordModel> update(StorageRecordModel record);
  Future<void> delete(int id);
  Future<void> deleteCascade(int id);
}

class StorageRepository implements StorageRepositoryBase {
  StorageRepository(this._client, {RepositoryReadCache? readCache})
    : _readCache = readCache;

  final SupabaseClient _client;
  final RepositoryReadCache? _readCache;

  Future<List<T>> _read<T>(String key, Future<List<T>> Function() load) =>
      _readCache?.read<T>(key, load) ?? load();

  Future<String> generateStorageCode() async {
    final res = await _client.rpc('generate_storage_code');
    return res as String;
  }

  Future<List<StorageRecordModel>> getAll() =>
      _read('StorageRepository.getAll', () async {
        final res = await _client
            .from('storage_records')
            .select()
            .order('storage_date', ascending: false);
        return (res as List)
            .map(
              (e) => StorageRecordModel.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList();
      });

  Future<List<StorageRecordModel>> getByCustomer(String customerName) async {
    final res = await _client
        .from('storage_records')
        .select()
        .eq('customer_name', customerName)
        .order('storage_date', ascending: false);
    return (res as List)
        .map(
          (e) =>
              StorageRecordModel.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  }

  /// 储值时间在 [start]～[end]（含）内的储值记录，仅比较日期部分
  Future<List<StorageRecordModel>> getByStorageDateRange(
    DateTime start,
    DateTime end,
  ) => _read(
    'StorageRepository.getByStorageDateRange:${start.year}-${start.month}-${start.day}:${end.year}-${end.month}-${end.day}',
    () async {
      final startDate = DateTime(start.year, start.month, start.day);
      final endDate = DateTime(end.year, end.month, end.day);
      final startStr =
          '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}';
      final endStr =
          '${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}';
      final res = await _client
          .from('storage_records')
          .select()
          .gte('storage_date', startStr)
          .lte('storage_date', endStr)
          .order('storage_date', ascending: false);
      return (res as List)
          .map(
            (e) => StorageRecordModel.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
    },
  );

  Future<StorageRecordModel?> getById(int id) async {
    final res = await _client
        .from('storage_records')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (res == null) return null;
    return StorageRecordModel.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<List<StorageRecordModel>> getByIds(Iterable<int> ids) async {
    final uniqueIds = ids.toSet().toList();
    if (uniqueIds.isEmpty) return [];

    final records = <StorageRecordModel>[];
    const chunkSize = 120;
    for (var offset = 0; offset < uniqueIds.length; offset += chunkSize) {
      final end = (offset + chunkSize < uniqueIds.length)
          ? offset + chunkSize
          : uniqueIds.length;
      final res = await _client
          .from('storage_records')
          .select()
          .inFilter('id', uniqueIds.sublist(offset, end));
      records.addAll(
        (res as List).map(
          (e) =>
              StorageRecordModel.fromJson(Map<String, dynamic>.from(e as Map)),
        ),
      );
    }
    return records;
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
    try {
      final owner = _client.auth.currentUser?.id;
      final code = await generateStorageCode();
      if (owner == null || _client.auth.currentUser?.id != owner) {
        throw StateError('登录账号已变化，请重新打开页面');
      }
      final data = record.toJson();
      data['code'] = code;
      final res = await _client
          .from('storage_records')
          .insert(data)
          .select()
          .single();
      return StorageRecordModel.fromJson(Map<String, dynamic>.from(res as Map));
    } finally {
      _readCache?.clear();
    }
  }

  Future<StorageRecordModel> update(StorageRecordModel record) async {
    try {
      final res = await _client
          .from('storage_records')
          .update(record.toJson())
          .eq('id', record.id)
          .select()
          .single();
      return StorageRecordModel.fromJson(Map<String, dynamic>.from(res as Map));
    } finally {
      _readCache?.clear();
    }
  }

  Future<void> delete(int id) async {
    try {
      await _client.from('storage_records').delete().eq('id', id);
    } finally {
      _readCache?.clear();
    }
  }

  /// 级联删除交给数据库外键在同一事务中完成，避免客户端半删。
  Future<void> deleteCascade(int id) async {
    try {
      await _client.from('storage_records').delete().eq('id', id);
    } finally {
      _readCache?.clear();
    }
  }
}
