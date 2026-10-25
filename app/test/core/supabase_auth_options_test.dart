import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yiyangnian/core/supabase_auth_options.dart';

class DelayedStore extends LocalStorage {
  final removal = Completer<void>();
  String? value = 'old-session';
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasAccessToken() async => value != null;
  @override
  Future<String?> accessToken() async => value;
  @override
  Future<void> persistSession(String session) async {
    value = session;
  }

  @override
  Future<void> removePersistedSession() async {
    await removal.future;
    value = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'gateway preserves the original account session and namespace',
    () async {
      const aliasKey = 'sb-yiyangnian-api-auth-token';
      SharedPreferences.setMockInitialValues({
        originalSessionKey: 'original-session-fixture',
        aliasKey: 'other-session-fixture',
      });
      final storage = supabaseAuthOptions('https://$gatewayHost').localStorage!;
      await storage.initialize();
      expect(await storage.accessToken(), 'original-session-fixture');
      await storage.persistSession('refreshed-session-fixture');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(originalSessionKey), 'refreshed-session-fixture');
      await storage.removePersistedSession();
      expect(prefs.containsKey(originalSessionKey), false);
      expect(prefs.getString(aliasKey), 'other-session-fixture');
    },
  );

  test('CloudBase uses a separate persisted session namespace', () async {
    SharedPreferences.setMockInitialValues({
      originalSessionKey: 'old-supabase-session',
      cloudBaseSessionKey: 'cloudbase-session',
    });
    final storage = supabaseAuthOptions(
      'https://yiyangnian-shanghai-d0b1453112fa.api.tcloudbasegateway.com',
    ).localStorage!;
    await storage.initialize();
    expect(await storage.accessToken(), 'cloudbase-session');
    await storage.persistSession('refreshed-cloudbase-session');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(cloudBaseSessionKey), 'refreshed-cloudbase-session');
    expect(prefs.getString(originalSessionKey), 'old-supabase-session');
  });

  test(
    'delayed SDK removal is serialized before the new persisted login',
    () async {
      final inner = DelayedStore();
      final storage = QueuedSessionStorage(inner);
      final removal = storage.removePersistedSession();
      final persist = storage.persistSession('new-session');
      await Future<void>.delayed(Duration.zero);
      expect(inner.value, 'old-session');
      inner.removal.complete();
      await Future.wait([removal, persist]);
      expect(await storage.accessToken(), 'new-session');
    },
  );

  test('original and unrelated projects keep SDK storage defaults', () {
    for (final url in [
      'https://jhntjagskjklbrsgturh.supabase.co',
      'https://other-project.supabase.co',
    ]) {
      expect(supabaseAuthOptions(url).localStorage, isNull);
    }
  });
}
