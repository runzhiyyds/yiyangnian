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

  group('CloudBase compatibility', () {
    final cloudBase = Uri.parse(
      'https://yiyangnian-shanghai-d0b1453112fa.api.tcloudbasegateway.com',
    );

    test('maps app email to the existing CloudBase username', () {
      expect(
        cloudBaseUsernameForEmail(' 18613544351@163.COM '),
        'u_18613544351_163_com',
      );
      expect(
        cloudBaseUsernameForEmail('User@example.com'),
        'u_user_example_com',
      );
    });

    test('rewrites PostgREST path and removes Supabase apikey', () async {
      late http.BaseRequest forwarded;
      final client = SupabaseHttpClient(
        inner: _Transport((request) async {
          forwarded = request;
          return http.StreamedResponse(Stream.value(utf8.encode('[]')), 200);
        }),
      );

      final response = await client.get(
        cloudBase.replace(path: '/rest/v1/customers', query: 'select=name'),
        headers: {
          'apikey': 'legacy-anon-key',
          'authorization': 'Bearer access-token',
        },
      );

      expect(forwarded.url.path, '/v1/rdb/rest/customers');
      expect(forwarded.url.query, 'select=name');
      expect(forwarded.headers, isNot(contains('apikey')));
      expect(forwarded.headers['authorization'], 'Bearer access-token');
      expect(response.body, '[]');
      client.close();
    });

    test(
      'adapts password grant and enriches token with a Supabase user',
      () async {
        var calls = 0;
        final client = SupabaseHttpClient(
          inner: _Transport((request) async {
            calls++;
            if (calls == 1) {
              expect(request.url.path, '/auth/v1/token');
              expect(request.url.hasQuery, isFalse);
              expect(request.headers, isNot(contains('apikey')));
              expect(request.headers, isNot(contains('authorization')));
              final body = jsonDecode(await request.finalize().bytesToString());
              expect(body, {
                'password': 'test-password',
                'username': 'u_user_example_com',
                'grant_type': 'password',
              });
              return http.StreamedResponse(
                Stream.value(
                  utf8.encode(
                    jsonEncode({
                      'token_type': 'Bearer',
                      'access_token': 'header.payload.signature',
                      'refresh_token': 'refresh-token',
                      'expires_in': 7200,
                      'sub': '2114251442994114561',
                    }),
                  ),
                ),
                200,
                request: request,
              );
            }
            expect(request.method, 'GET');
            expect(request.url.path, '/auth/v1/user/me');
            expect(
              request.headers['authorization'],
              'Bearer header.payload.signature',
            );
            return http.StreamedResponse(
              Stream.value(
                utf8.encode(
                  jsonEncode({
                    'sub': '2114251442994114561',
                    'email': 'User@example.com',
                    'username': 'u_user_example_com',
                    'created_at': '2026-10-25T00:00:00Z',
                    'email_verified': true,
                  }),
                ),
              ),
              200,
              request: request,
            );
          }),
        );

        final response = await client.post(
          cloudBase.replace(
            path: '/auth/v1/token',
            queryParameters: {'grant_type': 'password'},
          ),
          headers: {
            'apikey': 'cloudbase-public',
            'authorization': 'Bearer cloudbase-public',
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'email': 'User@example.com',
            'password': 'test-password',
            'gotrue_meta_security': {'captcha_token': null},
          }),
        );
        final payload = jsonDecode(response.body) as Map<String, dynamic>;
        expect(payload['sub'], '2114251442994114561');
        expect(payload['user']['id'], '2114251442994114561');
        expect(payload['user']['email'], 'User@example.com');
        expect(calls, 2);
        client.close();
      },
    );

    test('maps get user response to the direct GoTrue user shape', () async {
      final client = SupabaseHttpClient(
        inner: _Transport((request) async {
          expect(request.url.path, '/auth/v1/user/me');
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(
                jsonEncode({
                  'sub': '2114251442994114561',
                  'email': 'User@example.com',
                }),
              ),
            ),
            200,
            request: request,
          );
        }),
      );
      final response = await client.get(
        cloudBase.replace(path: '/auth/v1/user'),
        headers: {'authorization': 'Bearer access-token'},
      );
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      expect(payload['id'], '2114251442994114561');
      expect(payload, isNot(contains('user')));
      client.close();
    });

    test('adapts refresh grant without exposing legacy headers', () async {
      var calls = 0;
      final client = SupabaseHttpClient(
        inner: _Transport((request) async {
          calls++;
          if (calls == 1) {
            final body = jsonDecode(await request.finalize().bytesToString());
            expect(request.url.path, '/auth/v1/token');
            expect(request.url.hasQuery, isFalse);
            expect(request.headers, isNot(contains('apikey')));
            expect(request.headers, isNot(contains('authorization')));
            expect(body, {
              'refresh_token': 'old-refresh-token',
              'grant_type': 'refresh_token',
            });
            return http.StreamedResponse(
              Stream.value(
                utf8.encode(
                  jsonEncode({
                    'token_type': 'Bearer',
                    'access_token': 'new.header.token',
                    'refresh_token': 'new-refresh-token',
                    'expires_in': 7200,
                    'sub': '2114251442994114561',
                  }),
                ),
              ),
              200,
              request: request,
            );
          }
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(jsonEncode({'sub': '2114251442994114561'})),
            ),
            200,
            request: request,
          );
        }),
      );
      final response = await client.post(
        cloudBase.replace(
          path: '/auth/v1/token',
          queryParameters: {'grant_type': 'refresh_token'},
        ),
        headers: {
          'apikey': 'cloudbase-public',
          'authorization': 'Bearer expired-token',
          'content-type': 'application/json',
        },
        body: jsonEncode({'refresh_token': 'old-refresh-token'}),
      );
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      expect(payload['refresh_token'], 'new-refresh-token');
      expect(payload['user']['id'], '2114251442994114561');
      expect(calls, 2);
      client.close();
    });

    test(
      'preserves REST write body and never replays a failed write',
      () async {
        var calls = 0;
        final client = SupabaseHttpClient(
          inner: _Transport((request) async {
            calls++;
            expect(request.url.path, '/v1/rdb/rest/customers');
            expect(await request.finalize().bytesToString(), '{"name":"test"}');
            throw http.ClientException('response lost');
          }),
        );
        await expectLater(
          client.post(
            cloudBase.replace(path: '/rest/v1/customers'),
            headers: {
              'apikey': 'cloudbase-public',
              'authorization': 'Bearer access-token',
              'content-type': 'application/json',
            },
            body: '{"name":"test"}',
          ),
          throwsA(isA<http.ClientException>()),
        );
        expect(calls, 1);
        client.close();
      },
    );
  });
}
