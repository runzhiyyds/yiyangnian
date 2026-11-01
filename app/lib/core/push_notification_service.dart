import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../router.dart';
import 'config.dart';
import 'network/supabase_http_client.dart';

/// 处理后台消息的顶层函数（必须是顶层，并加入口点标记）
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('FCM background message: ${message.messageId} ${message.data}');
}

class PushNotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  static String? _deviceToken;
  static Future<void> _deviceOperations = Future<void>.value();

  static Future<void> _enqueue(Future<void> Function() work) {
    final next = _deviceOperations
        .catchError((Object _) {})
        .then((_) => work());
    _deviceOperations = next;
    return next;
  }

  static Future<void> syncCurrentDevice({SupabaseClient? client}) =>
      _refreshAndUploadToken(client: client);

  static Future<void> releaseCurrentDevice({SupabaseClient? client}) async {
    if (!Config.isBackendConfigured) return;
    final current = client ?? Supabase.instance.client;
    final jwt = current.auth.currentSession?.accessToken;
    final token = _deviceToken;
    // Never request an unavailable FCM token while the user is logging out.
    if (jwt == null || token == null) return;
    await _enqueue(
      () =>
          _postDeviceRpc('release_push_device', {'p_device_token': token}, jwt),
    );
  }

  static Future<void> _postDeviceRpc(
    String function,
    Map<String, String> body,
    String jwt,
  ) async {
    final transport = SupabaseHttpClient(timeout: const Duration(seconds: 3));
    try {
      final response = await transport.post(
        Uri.parse('${Config.backendUrl}/rest/v1/rpc/$function'),
        headers: {
          'apikey': Config.backendKey,
          'authorization': 'Bearer $jwt',
          'content-type': 'application/json',
        },
        body: jsonEncode(body),
      );
      if (response.statusCode >= 400)
        debugPrint('Push RPC $function failed: ${response.statusCode}');
    } catch (e) {
      debugPrint('Push RPC $function skipped: ${e.runtimeType}');
    } finally {
      transport.close();
    }
  }

  static Future<void> initialize() async {
    // Web 未配置 FirebaseOptions 时无法初始化；本地调试 run_web 不走 FCM
    if (kIsWeb) {
      debugPrint('PushNotificationService: skip on Web (no FCM in this build)');
      return;
    }
    // 初始化 Firebase（若已经初始化则直接返回）
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint(
        'PushNotificationService: Firebase.initializeApp failed (may already init): $e',
      );
    }

    // 注册后台消息处理
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Android 13+ 需要显式请求通知权限；iOS 以后也可复用此逻辑
    try {
      await _messaging.requestPermission();
    } catch (e, stack) {
      debugPrint(
        'Push permission request failed, will continue without push: $e\n$stack',
      );
    }

    // 获取并上报当前 Token（在不支持 GMS 的设备上会失败，这里做降级处理）
    await _refreshAndUploadToken();

    // 监听 Token 变更
    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      _uploadToken(token);
    });

    // 前台消息：简单在控制台打印，后续可扩展为 App 内 Banner
    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('FCM onMessage: ${message.messageId} ${message.data}');
    });

    // 用户点击通知进入 App 时，根据 data 导航
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleNotificationNavigation(message);
    });

    // App 冷启动时携带的通知
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationNavigation(initialMessage);
    }
  }

  static Future<void> _refreshAndUploadToken({SupabaseClient? client}) async {
    try {
      final token = await _messaging.getToken().timeout(
        const Duration(seconds: 3),
      );
      if (token != null) {
        await _uploadToken(token, client: client);
      }
    } catch (e, stack) {
      // 例如在没有 Google Play 服务的华为设备上：MISSING_INSTANCEID_SERVICE
      debugPrint(
        'FCM getToken failed, disable push on this device: $e\n$stack',
      );
    }
  }

  static Future<void> _uploadToken(
    String token, {
    SupabaseClient? client,
  }) async {
    _deviceToken = token;
    final current = client ?? Supabase.instance.client;
    final jwt = current.auth.currentSession?.accessToken;
    if (jwt == null) return;
    await _enqueue(() async {
      if (current.auth.currentSession?.accessToken != jwt) return;
      await _postDeviceRpc('claim_push_device', {
        'p_device_token': token,
        'p_platform': 'android',
      }, jwt);
    });
  }

  static void _handleNotificationNavigation(RemoteMessage message) {
    final data = message.data;
    final type = data['type'] as String?;
    final context = AppRouter.rootNavigatorKey.currentContext;
    if (context == null) return;

    switch (type) {
      case 'birthday_weekly':
        // 跳转到 TAB3 店铺数据分析，并定位到「近期生日提醒」区域
        context.go('/home/storage?scrollTo=birthday');
        break;
      case 'daily_report':
        // 跳转到 TAB3 店铺数据分析顶部
        context.go('/home/storage?scrollTo=top');
        break;
      default:
        // 其他类型暂不处理，保留默认行为
        break;
    }
  }
}
