import 'package:supabase_flutter/supabase_flutter.dart';

import 'inventory_models.dart';

class InventoryPurchaseRepository {
  InventoryPurchaseRepository(this._client);

  final SupabaseClient _client;

  Future<String> generatePurchaseCode() async {
    final res = await _client.rpc('generate_inventory_purchase_code');
    return res as String;
  }

  Future<List<InventoryPurchaseRecordModel>> getAll() async {
    final res = await _client
        .from('inventory_purchase_records')
        .select()
        .order('purchase_date', ascending: false)
        .order('id', ascending: false);
    return (res as List)
        .map((e) =>
            InventoryPurchaseRecordModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// 按进货日期（含首尾日期）查询进货单，供周期经营分析使用。
  Future<List<InventoryPurchaseRecordModel>> getByDateRange(
    DateTime start,
    DateTime end,
  ) async {
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
        .order('id', ascending: false);
    return (res as List)
        .map((e) => InventoryPurchaseRecordModel.fromJson(
            Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<InventoryPurchaseRecordModel?> getById(int id) async {
    final res = await _client
        .from('inventory_purchase_records')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (res == null) return null;
    return InventoryPurchaseRecordModel.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<InventoryPurchaseRecordModel> create(InventoryPurchaseRecordModel record) async {
    final code = await generatePurchaseCode();
    final data = record.toJson();
    data['code'] = code;
    final res = await _client
        .from('inventory_purchase_records')
        .insert(data)
        .select()
        .single();
    return InventoryPurchaseRecordModel.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<InventoryPurchaseRecordModel> update(InventoryPurchaseRecordModel record) async {
    final res = await _client
        .from('inventory_purchase_records')
        .update(record.toJson())
        .eq('id', record.id)
        .select()
        .single();
    return InventoryPurchaseRecordModel.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<void> delete(int id) async {
    await _client.from('inventory_purchase_records').delete().eq('id', id);
  }
}
