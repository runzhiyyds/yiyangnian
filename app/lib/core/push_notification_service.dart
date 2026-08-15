import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../router.dart';

/// 处理后台消息的顶层函数（必须是顶层，并加入口点标记）
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('FCM background message: ${message.messageId} ${message.data}');
}

class PushNotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  static Future<void> syncCurrentDevice() => _refreshAndUploadToken();

  static Future<void> releaseCurrentDevice() async {
    final client = Supabase.instance.client;
    if (client.auth.currentUser == null) return;
    try {
      final token = await _messaging.getToken();
      if (token == null) return;
      await client.rpc(
        'release_push_device',
        params: {'p_device_token': token},
      );
    } catch (e) {
      debugPrint('Failed to release push token: $e');
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

  static Future<void> _refreshAndUploadToken() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        await _uploadToken(token);
      }
    } catch (e, stack) {
      // 例如在没有 Google Play 服务的华为设备上：MISSING_INSTANCEID_SERVICE
      debugPrint(
        'FCM getToken failed, disable push on this device: $e\n$stack',
      );
    }
  }

  static Future<void> _uploadToken(String token) async {
    final client = Supabase.instance.client;
    final ownerId = client.auth.currentUser?.id;
    if (ownerId == null) return;
    try {
      await client.rpc(
        'claim_push_device',
        params: {'p_device_token': token, 'p_platform': 'android'},
      );
    } catch (e) {
      debugPrint('Failed to upload push token: $e');
    }
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
