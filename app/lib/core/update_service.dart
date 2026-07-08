import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'config.dart';

class UpdateInfo {
  final String latestVersion;
  final String? androidUrl;
  final String? downloadPageUrl;
  final String? releaseNote;

  /// 若能拿到 APK 直链，可放在此处，优先用于应用内下载。
  final String? apkUrl;

  UpdateInfo({
    required this.latestVersion,
    this.androidUrl,
    this.downloadPageUrl,
    this.releaseNote,
    this.apkUrl,
  });
}

class DownloadProgress {
  final int received;
  final int total;

  const DownloadProgress({
    required this.received,
    required this.total,
  });

  double get progress {
    if (total <= 0) return 0;
    if (received <= 0) return 0;
    return received / total;
  }
}

class UpdateService {
  static const MethodChannel _channel = MethodChannel('app.update/channel');
  static Future<String> getCurrentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  /// 比较版本号，返回 true 表示 remote 比 current 新
  static bool isNewerVersion(String current, String remote) {
    final c = _parseVersion(current);
    final r = _parseVersion(remote);
    for (var i = 0; i < 3; i++) {
      final cv = i < c.length ? c[i] : 0;
      final rv = i < r.length ? r[i] : 0;
      if (rv > cv) return true;
      if (rv < cv) return false;
    }
    return false;
  }

  static List<int> _parseVersion(String v) {
    return v.split('.').map((s) => int.tryParse(s) ?? 0).toList();
  }

  static Future<UpdateInfo?> checkUpdate() async {
    if (!Config.hasUpdateCheck) return null;
    try {
      final res = await http.get(Uri.parse(Config.updateCheckUrl)).timeout(
        const Duration(seconds: 10),
      );
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body) as Map<String, dynamic>?;
      if (json == null) return null;
      final latest = json['latest_version'] as String?;
      if (latest == null || latest.isEmpty) return null;
      return UpdateInfo(
        latestVersion: latest,
        androidUrl: json['android_url'] as String?,
        downloadPageUrl: json['download_page_url'] as String?,
        releaseNote: json['release_note'] as String?,
        apkUrl: json['android_url'] as String?,
      );
    } catch (e) {
      debugPrint('UpdateService.checkUpdate failed: $e');
      return null;
    }
  }

  /// 蒲公英版本检测：POST apiv2/app/check，若有新版本返回 [UpdateInfo]
  static Future<UpdateInfo?> checkUpdatePgyer() async {
    if (!Config.hasPgyerCheck) return null;
    try {
      final current = await getCurrentVersion();
      final body = '_api_key=${Uri.encodeComponent(Config.pgyerApiKey)}'
          '&appKey=${Uri.encodeComponent(Config.pgyerAppKey)}'
          '&buildVersion=${Uri.encodeComponent(current)}';
      final res = await http
          .post(
            Uri.parse('https://api.pgyer.com/apiv2/app/check'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: body,
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        return null;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>?;
      if (data == null) return null;
      // 蒲公英返回形如：{ code, message, data: { buildHaveNewVersion, buildVersion, ... } }
      final d = data['data'] as Map<String, dynamic>?;
      if (d == null) return null;
      final buildHaveNewVersion = d['buildHaveNewVersion'] as bool? ?? false;
      final buildVersion =
          (d['buildVersion'] ?? d['buildVersionNo']) as String?;
      if (buildVersion == null || buildVersion.isEmpty) return null;
      final directUrl =
          (d['downloadURL'] ?? d['downloadUrl']) as String?;
      final pageUrl = (d['appUrl'] ?? d['appURl']) as String?;
      return UpdateInfo(
        latestVersion: buildVersion,
        androidUrl: directUrl,
        downloadPageUrl: pageUrl,
        releaseNote: d['buildUpdateDescription'] as String?,
        apkUrl: directUrl,
      );
    } catch (e) {
      debugPrint('UpdateService.checkUpdate failed: $e');
      return null;
    }
  }

  static Future<bool> openDownload(String? url) async {
    if (url == null || url.isEmpty) return false;
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// 下载 APK 文件到本地，下载过程可通过 [onProgress] 回调观察进度。
  static Future<File> downloadApk(
    String url, {
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      throw ArgumentError('Invalid download url: $url');
    }
    final client = http.Client();
    try {
      final request = http.Request('GET', uri);
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw HttpException(
          'Download failed, status code ${response.statusCode}',
          uri: uri,
        );
      }
      final total = response.contentLength ?? -1;
      final dir = await _resolveApkDirectory();
      final file = File(
        '${dir.path}/update-${DateTime.now().millisecondsSinceEpoch}.apk',
      );
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);
        if (onProgress != null) {
          onProgress(
            DownloadProgress(
              received: received,
              total: total,
            ),
          );
        }
      }
      await sink.close();
      return file;
    } finally {
      client.close();
    }
  }

  static Future<Directory> _resolveApkDirectory() async {
    if (Platform.isAndroid) {
      final dir = await getExternalStorageDirectory();
      if (dir != null) return dir;
    }
    return getTemporaryDirectory();
  }

  /// 调起原生安装 APK，具体由 Android 端通过 FileProvider + Intent 处理。
  static Future<void> installApk(String filePath) async {
    if (!Platform.isAndroid) return;
    if (filePath.isEmpty) return;
    await _channel.invokeMethod('installApk', {'filePath': filePath});
  }
}
