import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yiyangnian/features/auth/auth_service.dart';

class SessionStore extends LocalStorage {
  bool removed = false;
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasAccessToken() async => !removed;
  @override
  Future<String?> accessToken() async => null;
  @override
  Future<void> persistSession(String session) async {
    removed = false;
  }

  @override
  Future<void> removePersistedSession() async {
    removed = true;
  }
}

String encode(Object value) =>
    base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
Map<String, dynamic> loginResponse(String id) => {
  'access_token':
      '${encode({'alg': 'HS256'})}.${encode({'sub': id, 'exp': 4102444800})}.signature',
  'token_type': 'bearer',
  'expires_in': 3600,
  'refresh_token': 'test-refresh-$id',
  'user': {
    'id': id,
    'aud': 'authenticated',
    'email': '$id@example.com',
    'created_at': '2026-10-13T00:00:00Z',
    'app_metadata': {},
    'user_metadata': {},
  },
};
void main() {
  test(
    'local logout does not wait for push or remote; delayed logout cannot erase next login',
    () async {
      final remote = Completer<http.Response>();
      final push = Completer<void>();
      var login = 0;
      final client = SupabaseClient(
        'https://test.supabase.co',
        'anon',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/logout')) return remote.future;
          return http.Response(
            jsonEncode(loginResponse('${++login}')),
            200,
            request: request,
          );
        }),
      );
      final store = SessionStore();
      var accountChanges = 0;
      final auth = AuthService.withOptions(
        client,
        sessionStorage: store,
        releaseDevice: (_) => push.future,
        onAccountChanged: () => accountChanges++,
      );
      try {
        await auth.signIn('1@example.com', 'test');
        expect(auth.isLoggedIn, true);
        final watch = Stopwatch()..start();
        await Future.wait([
          auth.signOut(),
          auth.signOut(),
        ]).timeout(const Duration(seconds: 1));
        expect(watch.elapsedMilliseconds, lessThan(1000));
        expect(auth.isLoggedIn, false);
        expect(client.auth.currentSession, null);
        expect(store.removed, true);
        expect(remote.isCompleted, false);
        expect(push.isCompleted, false);
        await auth.signIn('2@example.com', 'test');
        remote.complete(http.Response('', 204));
        push.complete();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(auth.user?.id, '2');
        expect(client.auth.currentUser?.id, '2');
        expect(accountChanges, 3);
      } finally {
        if (!remote.isCompleted) remote.complete(http.Response('', 204));
        if (!push.isCompleted) push.complete();
        auth.dispose();
        await client.dispose();
      }
    },
  );
  test(
    'offline remote logout still clears memory and persisted session',
    () async {
      final client = SupabaseClient(
        'https://test.supabase.co',
        'anon',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/logout'))
            throw http.ClientException('offline');
          return http.Response(
            jsonEncode(loginResponse('A')),
            200,
            request: request,
          );
        }),
      );
      final store = SessionStore();
      final auth = AuthService.withOptions(
        client,
        sessionStorage: store,
        enablePush: false,
      );
      try {
        await auth.signIn('A@example.com', 'test');
        await auth.signOut();
        expect(auth.user, null);
        expect(store.removed, true);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      } finally {
        auth.dispose();
        await client.dispose();
      }
    },
  );
}
