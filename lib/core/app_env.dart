/// Configuracion de entorno.
///
/// Las credenciales NO se escriben en el codigo: entran por `--dart-define`
/// (o `--dart-define-from-file`) al compilar. Ver `env/dev.example.json`.
///
/// La anon key de Supabase es publica por diseno (viaja dentro del APK),
/// pero aun asi no se versiona: cambiarla no debe implicar recompilar el
/// repositorio, y asi dev y produccion no comparten base por accidente.
/// Lo que protege los datos es Row Level Security, no el secreto de la key.
class AppEnv {
  const AppEnv._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Equipo que muestra la app mientras no exista seleccion del usuario.
  /// Por defecto, el club creado por `supabase/seed.sql`.
  static const String defaultTeamId = String.fromEnvironment(
    'DEFAULT_TEAM_ID',
    defaultValue: 'a0000000-0000-4000-8000-000000000001',
  );

  /// Si falta cualquiera de las dos credenciales la app arranca igual,
  /// en modo local, con los datos de ejemplo. Sirve para que el proyecto
  /// siga corriendo sin backend (demos, clase, primer arranque).
  static bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
