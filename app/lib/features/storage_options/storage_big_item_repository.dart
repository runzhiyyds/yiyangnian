import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/repository_read_cache.dart';

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
  StorageBigItemRepository(this._client, {RepositoryReadCache? readCache})
    : _readCache = readCache;

  final SupabaseClient _client;
  final RepositoryReadCache? _readCache;

  Future<List<T>> _read<T>(String key, Future<List<T>> Function() load) =>
      _readCache?.read<T>(key, load) ?? load();

  Future<List<StorageBigItemOption>> getAll() =>
      _read('StorageBigItemRepository.getAll', () async {
        final res = await _client
            .from('storage_big_item_options')
            .select()
            .order('name');
        return (res as List)
            .map(
              (e) => StorageBigItemOption.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList();
      });

  Future<StorageBigItemOption> getOrCreate(String name) async {
    try {
      final trimmed = name.trim();
      if (trimmed.isEmpty) throw ArgumentError('储值大项名称不能为空');
      final existing = await _client
          .from('storage_big_item_options')
          .select()
          .eq('name', trimmed)
          .maybeSingle();
      if (existing != null) {
        return StorageBigItemOption.fromJson(
          Map<String, dynamic>.from(existing as Map),
        );
      }
      final res = await _client
          .from('storage_big_item_options')
          .insert({'name': trimmed})
          .select()
          .single();
      return StorageBigItemOption.fromJson(
        Map<String, dynamic>.from(res as Map),
      );
    } finally {
      _readCache?.clear();
    }
  }
}
