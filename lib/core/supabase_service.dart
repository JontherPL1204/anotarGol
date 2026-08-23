import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_env.dart';

/// Punto unico de acceso al backend.
///
/// Ningun widget debe llamar a `Supabase.instance.client` directamente:
/// pasan por los repositorios de `lib/repositories/`, y esos pasan por aca.
class SupabaseService {
  const SupabaseService._();

  static bool _initialized = false;

  /// `true` si la app tiene backend. Si es `false`, la UI debe seguir
  /// funcionando con datos locales en vez de reventar.
  static bool get isReady => _initialized;

  /// Se llama una sola vez desde `main()`, antes de `runApp`.
  ///
  /// Nunca lanza excepcion: si el backend no esta configurado o no
  /// responde, la app arranca en modo local en lugar de quedarse en
  /// pantalla negra.
  static Future<void> init() async {
    if (_initialized || !AppEnv.isSupabaseConfigured) return;

    try {
      await Supabase.initialize(
        url: AppEnv.supabaseUrl,
        anonKey: AppEnv.supabaseAnonKey,
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
        ),
      );
      _initialized = true;
    } catch (_) {
      _initialized = false;
    }
  }

  static SupabaseClient get client {
    if (!_initialized) {
      throw StateError(
        'Supabase no esta inicializado. Compila con '
        '--dart-define-from-file=env/dev.json o revisa SupabaseService.isReady '
        'antes de usar los repositorios.',
      );
    }
    return Supabase.instance.client;
  }

  static User? get currentUser => _initialized ? client.auth.currentUser : null;

  static bool get isSignedIn => currentUser != null;
}
