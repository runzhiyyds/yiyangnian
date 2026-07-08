# 颐养年 - Release 构建保留规则
# 若 Release 出现 Failed host lookup 而 Debug 正常，保留网络相关类避免 R8 误删/混淆

# Supabase / GoTrue / 网络请求
-keep class io.supabase.** { *; }
-keep class com.supabase.** { *; }
-dontwarn io.supabase.**

# OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**
-keepnames class okhttp3.internal.huc.HttpURLConnectionImpl
-keep class okhttp3.** { *; }

# 保留 Dart/Flutter 与 JNI
-keep class io.flutter.** { *; }
