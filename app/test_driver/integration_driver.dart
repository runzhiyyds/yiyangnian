import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:integration_test/common.dart';

/// Select the test extension rather than the first Firebase/background isolate.
Future<void> main() async {
  final base = Uri.parse(Platform.environment['VM_SERVICE_URL']!);
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, String> params = const {},
    Duration timeout = const Duration(seconds: 10),
  ]) async {
    final uri = base.resolve(method).replace(queryParameters: params);
    final request = await http.getUrl(uri).timeout(timeout);
    final response = await request.close().timeout(timeout);
    final result =
        jsonDecode(await utf8.decoder.bind(response).join().timeout(timeout))
            as Map<String, dynamic>;
    if (result['error'] != null) throw StateError('VM service request failed');
    return result['result'] as Map<String, dynamic>;
  }

  try {
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    String? target;
    while (target == null && DateTime.now().isBefore(deadline)) {
      final vm = await call('getVM');
      for (final ref in vm['isolates'] as List) {
        final id = ref['id'] as String;
        final isolate = await call('getIsolate', {'isolateId': id});
        if (isolate['pauseEvent']?['kind'] == 'PauseStart') {
          await call('resume', {'isolateId': id});
        }
        if ((isolate['extensionRPCs'] as List? ?? []).contains(
          'ext.flutter.driver',
        )) {
          target = id;
          break;
        }
      }
      if (target == null) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    if (target == null) {
      throw StateError('Integration test extension did not start');
    }
    // --start-paused also applies to JSON isolates spawned lazily by the SDK.
    // Resume only startup pauses while collecting the report.
    var collecting = true;
    final resumeWorkers = (() async {
      while (collecting) {
        final vm = await call('getVM');
        for (final ref in vm['isolates'] as List) {
          final id = ref['id'] as String;
          final isolate = await call('getIsolate', {'isolateId': id});
          if (isolate['pauseEvent']?['kind'] == 'PauseStart') {
            await call('resume', {'isolateId': id});
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    })();
    late Map<String, dynamic> result;
    try {
      result = await call('ext.flutter.driver', {
        'isolateId': target,
        'command': 'request_data',
      }, const Duration(minutes: 3));
    } finally {
      collecting = false;
      await resumeWorkers;
    }
    final report = Response.fromJson(result['response']['message'] as String);
    if (!report.allTestsPassed) {
      stderr.writeln(report.formattedFailureDetails);
      exitCode = 1;
    } else {
      stdout.writeln('All integration tests passed; installed app retained.');
    }
  } finally {
    http.close(force: true);
  }
}
