/// 颐养年店铺管理 - Supabase 配置
/// 唯一来源：lib/core/env_generated.dart（由 scripts/generate_env_dart.sh 从 env.json 生成）。
/// 本地调试与发布包均使用该文件，保证行为完全一致。
import 'package:flutter/foundation.dart';

import 'env_generated.dart';

class Config {
  static const String cloudBaseEnvId = kCloudBaseEnvId;
  static const String backendUrl =
      'https://$cloudBaseEnvId.api.tcloudbasegateway.com';
  static const String backendKey = 'cloudbase-public';
  static const String supabaseUrl = kSupabaseUrl;
  static const String supabaseAnonKey = kSupabaseAnonKey;

  /// 检查更新接口 URL，返回 version.json 格式：{ latest_version, android_url, download_page_url, release_note }
  static const String updateCheckUrl = kUpdateCheckUrl;

  /// 蒲公英 App Key（应用管理 → 安装设置），用于启动页版本检测
  static const String pgyerAppKey = kPgyerAppKey;

  /// 蒲公英 API Key（账户设置 → API 信息），用于调用 app/check
  static const String pgyerApiKey = kPgyerApiKey;

  static bool get isSupabaseConfigured =>
      !supabaseUrl.contains('REPLACE_ME') &&
      !supabaseAnonKey.contains('REPLACE_ME');

  static bool get isBackendConfigured => cloudBaseEnvId.isNotEmpty;

  static bool get hasUpdateCheck => updateCheckUrl.isNotEmpty;

  /// 是否启用蒲公英版本检测（需同时配置 appKey 与 apiKey）
  static bool get hasPgyerCheck =>
      pgyerAppKey.isNotEmpty && pgyerApiKey.isNotEmpty;

  /// 用于设置页显示，便于对比 Debug/Release 是否同一配置（仅显示主机前缀）
  static String get supabaseHostDisplay {
    if (!isBackendConfigured) return '未配置';
    try {
      final uri = Uri.parse(backendUrl);
      final host = uri.host;
      if (host.length <= 12) return host;
      return '${host.substring(0, 8)}***${host.substring(host.length - 4)}';
    } catch (e) {
      debugPrint('config: _maskHost failed: $e');
      return backendUrl;
    }
  }
}
