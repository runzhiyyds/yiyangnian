import 'package:supabase_flutter/supabase_flutter.dart';

class StorageSmallItemOption {
  final int id;
  final String name;
  /// 归属的大项 ID，null 表示未归类
  final int? storageBigItemId;

  StorageSmallItemOption({
    required this.id,
    required this.name,
    this.storageBigItemId,
  });

  factory StorageSmallItemOption.fromJson(Map<String, dynamic> json) {
    return StorageSmallItemOption(
      id: json['id'] as int,
      name: json['name'] as String,
      storageBigItemId: json['storage_big_item_id'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'storage_big_item_id': storageBigItemId,
      };
}

class StorageSmallItemRepository {
  StorageSmallItemRepository(this._client);

  final SupabaseClient _client;

  Future<List<StorageSmallItemOption>> getAll() async {
    final res = await _client
        .from('storage_small_item_options')
        .select()
        .order('name');
    return (res as List)
        .map((e) =>
            StorageSmallItemOption.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// 按大项 ID 筛选小项；bigItemId 为 null 时返回未归类（storage_big_item_id 为 null）的小项
  Future<List<StorageSmallItemOption>> getByBigItemId(int? bigItemId) async {
    final all = await getAll();
    if (bigItemId == null) {
      return all.where((s) => s.storageBigItemId == null).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    }
    return all.where((s) => s.storageBigItemId == bigItemId).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<List<StorageSmallItemOption>> search(String query) async {
    if (query.trim().isEmpty) return getAll();
    final res = await _client
        .from('storage_small_item_options')
        .select()
        .ilike('name', '%$query%')
        .order('name');
    return (res as List)
        .map((e) =>
            StorageSmallItemOption.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<StorageSmallItemOption> update(int id, String name, {int? storageBigItemId}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('储值小项名称不能为空');
    final data = <String, dynamic>{'name': trimmed};
    if (storageBigItemId != null) {
      data['storage_big_item_id'] = storageBigItemId;
    }
    final res = await _client
        .from('storage_small_item_options')
        .update(data)
        .eq('id', id)
        .select()
        .single();
    return StorageSmallItemOption.fromJson(Map<String, dynamic>.from(res as Map));
  }

  /// 仅更新小项归属的大项
  Future<StorageSmallItemOption> updateBigItem(int id, int? bigItemId) async {
    final res = await _client
        .from('storage_small_item_options')
        .update({'storage_big_item_id': bigItemId})
        .eq('id', id)
        .select()
        .single();
    return StorageSmallItemOption.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<StorageSmallItemOption> getOrCreate(String name, {int? storageBigItemId}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('储值小项名称不能为空');
    final existing = await _client
        .from('storage_small_item_options')
        .select()
        .eq('name', trimmed)
        .maybeSingle();
    if (existing != null) {
      return StorageSmallItemOption.fromJson(
          Map<String, dynamic>.from(existing as Map));
    }
    final data = <String, dynamic>{'name': trimmed};
    if (storageBigItemId != null) {
      data['storage_big_item_id'] = storageBigItemId;
    }
    final res = await _client
        .from('storage_small_item_options')
        .insert(data)
        .select()
        .single();
    return StorageSmallItemOption.fromJson(Map<String, dynamic>.from(res as Map));
  }
}
