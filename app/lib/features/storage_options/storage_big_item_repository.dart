import 'package:supabase_flutter/supabase_flutter.dart';

class StorageBigItemOption {
  final int id;
  final String name;

  StorageBigItemOption({required this.id, required this.name});

  factory StorageBigItemOption.fromJson(Map<String, dynamic> json) {
    return StorageBigItemOption(
      id: json['id'] as int,
      name: json['name'] as String,
    );
  }
}

class StorageBigItemRepository {
  StorageBigItemRepository(this._client);

  final SupabaseClient _client;

  Future<List<StorageBigItemOption>> getAll() async {
    final res = await _client
        .from('storage_big_item_options')
        .select()
        .order('name');
    return (res as List)
        .map((e) =>
            StorageBigItemOption.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<StorageBigItemOption> getOrCreate(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('储值大项名称不能为空');
    final existing = await _client
        .from('storage_big_item_options')
        .select()
        .eq('name', trimmed)
        .maybeSingle();
    if (existing != null) {
      return StorageBigItemOption.fromJson(
          Map<String, dynamic>.from(existing as Map));
    }
    final res = await _client
        .from('storage_big_item_options')
        .insert({'name': trimmed})
        .select()
        .single();
    return StorageBigItemOption.fromJson(Map<String, dynamic>.from(res as Map));
  }
}
