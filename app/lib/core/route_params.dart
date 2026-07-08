import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

/// 类型安全的路由参数，由路由层从 [GoRouterState] 解析并校验后传入页面。
/// 解析失败时返回 null，由 router 展示占位或重定向。

class CustomerDetailParams {
  const CustomerDetailParams({required this.customerName});
  final String customerName;
  static CustomerDetailParams? fromState(GoRouterState state) {
    final name = state.extra is String ? state.extra as String? : null;
    if (name == null || name.isEmpty) return null;
    return CustomerDetailParams(customerName: name);
  }
}

class CustomerEditParams {
  const CustomerEditParams({required this.customerName});
  final String customerName;
  static CustomerEditParams? fromState(GoRouterState state) {
    final name = state.extra is String ? state.extra as String? : null;
    if (name == null || name.isEmpty) return null;
    return CustomerEditParams(customerName: name);
  }
}

class CustomerNewParams {
  const CustomerNewParams({this.templateName, this.initialName});
  final String? templateName;
  final String? initialName;
  static CustomerNewParams fromState(GoRouterState state) {
    final extra = state.extra is Map<String, dynamic> ? state.extra as Map<String, dynamic>? : null;
    final query = state.uri.queryParameters;
    String? template = extra?['template'] as String? ?? query['template'];
    if (template != null && template is! String) template = template.toString();
    // 仅对来自 URL query 的值解码，extra 中的已是原始字符串（含 % 等会触发 illegal percent encoding）
    if (template != null && extra?['template'] == null) {
      try {
        template = Uri.decodeQueryComponent(template);
      } catch (e) {
        debugPrint('route_params: Uri.decodeQueryComponent failed for template: $e');
      }
    }
    final initialName = extra?['initialName'] as String?;
    return CustomerNewParams(
      templateName: template,
      initialName: initialName,
    );
  }
}

class StorageDetailParams {
  const StorageDetailParams({required this.storageId});
  final int storageId;
  static StorageDetailParams? fromState(GoRouterState state) {
    final id = int.tryParse(state.pathParameters['id'] ?? '');
    if (id == null) return null;
    return StorageDetailParams(storageId: id);
  }
}

class StorageNewParams {
  const StorageNewParams({this.customerName, this.copyFromId});
  final String? customerName;
  final int? copyFromId;
  static StorageNewParams fromState(GoRouterState state) {
    final extra = state.extra is Map<String, dynamic> ? state.extra as Map<String, dynamic>? : null;
    final query = state.uri.queryParameters;
    String? customer = extra?['customer'] as String? ?? query['customer'];
    if (customer != null && customer is! String) customer = customer.toString();
    // 仅对来自 URL query 的值解码，extra 中的已是原始字符串（含 % 等会触发 illegal percent encoding）
    if (customer != null && extra?['customer'] == null) {
      try {
        customer = Uri.decodeQueryComponent(customer);
      } catch (e) {
        debugPrint('route_params: Uri.decodeQueryComponent failed for customer: $e');
      }
    }
    final copy = extra?['copy'];
    final copyFromId = copy is int ? copy : int.tryParse(copy?.toString() ?? '');
    return StorageNewParams(customerName: customer, copyFromId: copyFromId);
  }
}

class ConsumptionNewParams {
  const ConsumptionNewParams({this.storageId});
  final int? storageId;
  static ConsumptionNewParams fromState(GoRouterState state) {
    final extra = state.extra is Map<String, dynamic> ? state.extra as Map<String, dynamic>? : null;
    final storageFromExtra = extra?['storageId'];
    final storageFromQuery = state.uri.queryParameters['storage'];
    final id = storageFromExtra is int
        ? storageFromExtra
        : (storageFromExtra != null ? int.tryParse(storageFromExtra.toString()) : null)
            ?? (storageFromQuery != null ? int.tryParse(storageFromQuery) : null);
    return ConsumptionNewParams(storageId: id);
  }
}

class ConsumptionEditParams {
  const ConsumptionEditParams({this.consumptionId, this.storageId});
  final int? consumptionId;
  final int? storageId;
  static ConsumptionEditParams? fromState(GoRouterState state) {
    final idStr = state.pathParameters['id'];
    final id = idStr != null ? int.tryParse(idStr) : null;
    if (id == null && idStr != null) return null;
    return ConsumptionEditParams(consumptionId: id);
  }
}
