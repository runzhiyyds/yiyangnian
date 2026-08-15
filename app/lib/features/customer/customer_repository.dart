import 'package:supabase_flutter/supabase_flutter.dart';

import 'customer_model.dart';

/// 客户数据仓库抽象，便于单测注入 Mock/Fake。
abstract class CustomerRepositoryBase {
  Future<List<CustomerModel>> getAll();
  Future<CustomerModel?> getByName(String name);
  Future<bool> existsByName(String name, {String? excludeName});
  Future<CustomerModel> create(CustomerModel customer);
  Future<CustomerModel> update(String oldName, CustomerModel customer);
  Future<void> delete(String name);
  Future<void> deleteCascade(String name);
  Future<double> getTotalDeposit(String customerName);
  Future<DateTime?> getEarliestStorageDate(String customerName);
  Future<int> getTotalRemainingConsumption(String customerName);
  Future<List<String>> getStorageCodes(String customerName);
}

class CustomerRepository implements CustomerRepositoryBase {
  CustomerRepository(this._client);

  final SupabaseClient _client;

  Future<List<CustomerModel>> getAll() async {
    final res = await _client
        .from('customers')
        .select()
        .order('name');
    return (res as List)
        .map((e) => CustomerModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<CustomerModel?> getByName(String name) async {
    final res = await _client
        .from('customers')
        .select()
        .eq('name', name)
        .maybeSingle();
    if (res == null) return null;
    return CustomerModel.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<bool> existsByName(String name, {String? excludeName}) async {
    var query = _client.from('customers').select('name').eq('name', name);
    if (excludeName != null && excludeName.isNotEmpty) {
      query = query.neq('name', excludeName);
    }
    final res = await query.maybeSingle();
    return res != null;
  }

  Future<CustomerModel> create(CustomerModel customer) async {
    final res = await _client
        .from('customers')
        .insert(customer.toJson())
        .select()
        .single();
    return CustomerModel.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<CustomerModel> update(String oldName, CustomerModel customer) async {
    // 仅更新 customers；storage_records.customer_name 依赖外键 ON UPDATE CASCADE 自动同步
    // 若未执行迁移 007_customer_name_fk_on_update_cascade.sql，改名会报外键错误
    final res = await _client
        .from('customers')
        .update(customer.toJson())
        .eq('name', oldName)
        .select()
        .single();
    return CustomerModel.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<void> delete(String name) async {
    await _client.from('customers').delete().eq('name', name);
  }

  /// 级联删除交给数据库外键在同一事务中完成，避免客户端多请求导致半删状态。
  Future<void> deleteCascade(String name) async {
    await _client.from('customers').delete().eq('name', name);
  }

  /// 累计储值 = 该客户所有储值记录的 amount 之和
  Future<double> getTotalDeposit(String customerName) async {
    final res = await _client
        .from('storage_records')
        .select('amount')
        .eq('customer_name', customerName);
    double sum = 0;
    for (final row in res as List) {
      sum += (row['amount'] as num?)?.toDouble() ?? 0;
    }
    return sum;
  }

  /// 最早启用套盒时间 = 该客户所有储值记录的最早 storage_date
  Future<DateTime?> getEarliestStorageDate(String customerName) async {
    final res = await _client
        .from('storage_records')
        .select('storage_date')
        .eq('customer_name', customerName)
        .order('storage_date', ascending: true)
        .limit(1)
        .maybeSingle();
    if (res == null || res['storage_date'] == null) return null;
    return DateTime.parse(res['storage_date'] as String);
  }

  /// 剩余可消费总次数 = 所有储值的 (total_count - 消费记录数) 之和
  Future<int> getTotalRemainingConsumption(String customerName) async {
    final storages = await _client
        .from('storage_records')
        .select('id, total_count')
        .eq('customer_name', customerName);
    final rows = storages as List;
    if (rows.isEmpty) return 0;
    final storageIds = rows.map((s) => s['id'] as int).toList();
    final consumptions = await _client
        .from('consumption_records')
        .select('storage_record_id')
        .inFilter('storage_record_id', storageIds);
    final consumedByStorage = <int, int>{};
    for (final row in consumptions as List) {
      final storageId = row['storage_record_id'] as int;
      consumedByStorage.update(storageId, (count) => count + 1,
          ifAbsent: () => 1);
    }
    return rows.fold<int>(0, (total, storage) {
      final id = storage['id'] as int;
      final totalCount = storage['total_count'] as int? ?? 0;
      return total + totalCount - (consumedByStorage[id] ?? 0);
    });
  }

  /// 关联储值编号列表
  Future<List<String>> getStorageCodes(String customerName) async {
    final res = await _client
        .from('storage_records')
        .select('code')
        .eq('customer_name', customerName)
        .order('storage_date', ascending: false);
    return (res as List).map((e) => e['code'] as String).toList();
  }
}
