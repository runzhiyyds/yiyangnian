import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/app_providers.dart';
import 'core/config.dart';
import 'core/data_cache.dart';
import 'core/push_notification_service.dart';

void main() async {
  // 全局异常捕获：未捕获的异步异常与 Flutter 框架错误，避免直接崩溃。
  // 注意：必须在与 runApp 相同的 Zone 中初始化 FlutterBinding。
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      if (kReleaseMode) {
        // Release 下可上报到崩溃收集服务
        debugPrint('FlutterError: ${details.exceptionAsString()}');
      }
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('Uncaught error: $error\n$stack');
      return true; // 防止继续传播导致崩溃
    };

    if (Config.isSupabaseConfigured) {
      // supabase_flutter 默认将会话持久化到本地；用户首次登录后，同设备上更新/重启会恢复会话
      await Supabase.initialize(
        url: Config.supabaseUrl,
        anonKey: Config.supabaseAnonKey,
      );
    }
    final client = Config.isSupabaseConfigured ? Supabase.instance.client : null;
    final dataCache = DataCache(maxSize: 200);

    // Release 下展示友好错误页而非红屏
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return Material(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              kReleaseMode ? '页面出现错误，请重启应用' : details.exceptionAsString(),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    };

    // 初始化推送通知服务（FCM + Token 上报）。
    // 改为在后台异步初始化，避免在启动阶段被 FCM 阻塞（例如部分华为/Honor 机型）。
    unawaited(
      PushNotificationService.initialize().catchError((e, stack) {
        debugPrint('PushNotificationService init failed, continue without push: $e\n$stack');
      }),
    );

    runApp(
      MultiProvider(
        providers: buildAppProviders(dataCache, client),
        child: const YiyangnianApp(),
      ),
    );
  }, (error, stack) {
    debugPrint('Zone error: $error\n$stack');
  });
}
