import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yiyangnian/core/supabase_auth_options.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('gateway preserves the original account session and namespace', () async {
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
  });

  test('original and unrelated projects keep SDK storage defaults', () {
    for (final url in ['https://jhntjagskjklbrsgturh.supabase.co',
      'https://other-project.supabase.co']) {
      expect(supabaseAuthOptions(url).localStorage, isNull);
    }
  });
}
