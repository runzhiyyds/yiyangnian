import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:yiyangnian/core/network/supabase_http_client.dart';

class _Transport extends http.BaseClient {
  _Transport(this.handle);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handle;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handle(request);
}

void main() {
  final gateway = Uri.parse(
    'https://yiyangnian-api.pet-food-advisor.asia/rest/v1/items?select=id',
  );

  test('forwards method, headers, streaming body and response', () async {
    final client = SupabaseHttpClient(
      inner: _Transport((request) async {
        expect(request.method, 'POST');
        expect(request.headers['apikey'], 'test-key');
        expect(await request.finalize().bytesToString(), 'password-body');
        return http.StreamedResponse(
          Stream.value(utf8.encode('ok')),
          200,
          headers: {'content-type': 'text/plain'},
        );
      }),
    );
    final response = await client.post(
      Uri.parse('https://example.test/token'),
      headers: {'apikey': 'test-key'},
      body: 'password-body',
    );
    expect(response.statusCode, 200);
    expect(response.body, 'ok');
    client.close();
  });

  test('header timeout aborts the request and does not replay it', () async {
    var calls = 0;
    final aborted = Completer<void>();
    final client = SupabaseHttpClient(
      timeout: const Duration(milliseconds: 20),
      inner: _Transport((request) async {
        calls++;
        await (request as http.Abortable).abortTrigger;
        aborted.complete();
        throw http.RequestAbortedException(request.url);
      }),
    );
    await expectLater(
      client.get(Uri.parse('https://example.test/token')),
      throwsA(isA<TimeoutException>()),
    );
    await aborted.future;
    expect(calls, 1);
    client.close();
  });

  test('body stall shares the same deadline and is aborted', () async {
    late StreamController<List<int>> body;
    final client = SupabaseHttpClient(
      timeout: const Duration(milliseconds: 20),
      inner: _Transport((request) async {
        body = StreamController<List<int>>();
        unawaited(
          (request as http.Abortable).abortTrigger!.then((_) {
            body.addError(http.RequestAbortedException(request.url));
            body.close();
          }),
        );
        return http.StreamedResponse(body.stream, 200);
      }),
    );
    await expectLater(
      client.get(Uri.parse('https://example.test/data')),
      throwsA(isA<TimeoutException>()),
    );
    client.close();
  });

  test('one timeout leaves a concurrent successful request intact', () async {
    final client = SupabaseHttpClient(
      timeout: const Duration(milliseconds: 30),
      inner: _Transport((request) async {
        if (request.url.path == '/slow') {
          await (request as http.Abortable).abortTrigger;
          throw http.RequestAbortedException(request.url);
        }
        return http.StreamedResponse(Stream.value([111, 107]), 200);
      }),
    );
    final slow = expectLater(
      client.get(Uri.parse('https://example.test/slow')),
      throwsA(isA<TimeoutException>()),
    );
    final fast = await client.get(Uri.parse('https://example.test/fast'));
    expect(fast.body, 'ok');
    await slow;
    client.close();
  });

  test(
    'gateway GET retries one connection failure with the same headers',
    () async {
      var calls = 0;
      final client = SupabaseHttpClient(
        inner: _Transport((request) async {
          calls++;
          expect(request.url, gateway);
          expect(request.headers['authorization'], 'Bearer test-token');
          if (calls == 1) throw http.ClientException('connection failed');
          return http.StreamedResponse(Stream.value(utf8.encode('ok')), 200);
        }),
      );
      final response = await client.get(
        gateway,
        headers: {'authorization': 'Bearer test-token'},
      );
      expect(response.body, 'ok');
      expect(calls, 2);
      client.close();
    },
  );

  test('gateway GET retries a 502 once, but not an application 400', () async {
    var calls = 0;
    final client = SupabaseHttpClient(
      inner: _Transport((request) async {
        calls++;
        return http.StreamedResponse(
          Stream.value(utf8.encode(calls == 1 ? 'bad gateway' : 'ok')),
          calls == 1 ? 502 : 200,
        );
      }),
    );
    expect((await client.get(gateway)).body, 'ok');
    expect(calls, 2);
    client.close();

    var badRequestCalls = 0;
    final badRequestClient = SupabaseHttpClient(
      inner: _Transport((request) async {
        badRequestCalls++;
        return http.StreamedResponse(
          Stream.value(utf8.encode('bad request')),
          400,
        );
      }),
    );
    expect((await badRequestClient.get(gateway)).statusCode, 400);
    expect(badRequestCalls, 1);
    badRequestClient.close();
  });

  test(
    'gateway write is never replayed after an ambiguous transport error',
    () async {
      var calls = 0;
      final client = SupabaseHttpClient(
        inner: _Transport((request) async {
          calls++;
          throw http.ClientException('response lost');
        }),
      );
      await expectLater(
        client.post(gateway, body: '{}'),
        throwsA(isA<http.ClientException>()),
      );
      expect(calls, 1);
      client.close();
    },
  );

  test('gateway GET shares one deadline across attempts', () async {
    var calls = 0;
    final client = SupabaseHttpClient(
      timeout: const Duration(milliseconds: 30),
      inner: _Transport((request) async {
        calls++;
        if (calls == 1) throw http.ClientException('connection failed');
        await (request as http.Abortable).abortTrigger;
        throw http.RequestAbortedException(request.url);
      }),
    );
    await expectLater(client.get(gateway), throwsA(isA<TimeoutException>()));
    expect(calls, 2);
    client.close();
  });
}
