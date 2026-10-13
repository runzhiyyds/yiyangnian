import 'package:supabase_flutter/supabase_flutter.dart';

const gatewayHost = 'yiyangnian-api.pet-food-advisor.asia';
const originalSessionKey = 'sb-jhntjagskjklbrsgturh-auth-token';

/// This gateway is fixed to the original project; retain its existing session.
/// Other hosts keep the SDK default instead of inheriting another project's key.
FlutterAuthClientOptions supabaseAuthOptions(String url) =>
    FlutterAuthClientOptions(
      localStorage: Uri.parse(url).host == gatewayHost
          ? SharedPreferencesLocalStorage(persistSessionKey: originalSessionKey)
          : null,
    );
