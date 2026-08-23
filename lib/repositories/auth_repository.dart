import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_service.dart';

/// Registro, inicio y cierre de sesion.
///
/// El perfil en `public.profiles` lo crea un trigger de la base al
/// registrarse: la app no tiene que insertarlo.
class AuthRepository {
  const AuthRepository();

  SupabaseClient get _db => SupabaseService.client;

  User? get currentUser => SupabaseService.currentUser;
  bool get isSignedIn => SupabaseService.isSignedIn;

  /// Emite en cada login/logout/refresh de token.
  Stream<AuthState> get onAuthStateChange => _db.auth.onAuthStateChange;

  /// [cedula] viaja en el metadata del registro. Un trigger de la base
  /// la guarda en el perfil y le entrega al usuario las fichas de
  /// jugador que ya tuviera cargadas con esa misma cédula.
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    String? displayName,
    String? cedula,
  }) {
    final datos = <String, dynamic>{};
    if (displayName != null) datos['display_name'] = displayName;
    if (cedula != null) datos['cedula'] = cedula;

    return _db.auth.signUp(
      email: email,
      password: password,
      data: datos.isEmpty ? null : datos,
    );
  }

  /// Para quien ya tenía cuenta y agrega la cédula después. Devuelve
  /// cuántas fichas de jugador quedaron vinculadas.
  Future<int> registrarCedula(String cedula) async {
    final r = await _db.rpc('registrar_mi_cedula', params: {'p_cedula': cedula});
    return (r as num?)?.toInt() ?? 0;
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) =>
      _db.auth.signInWithPassword(email: email, password: password);

  Future<void> signOut() => _db.auth.signOut();

  Future<void> sendPasswordReset(String email) =>
      _db.auth.resetPasswordForEmail(email);

  /// Actualiza el nombre visible en `profiles`.
  Future<void> updateDisplayName(String displayName) async {
    final id = currentUser?.id;
    if (id == null) return;
    await _db.from('profiles').update({'display_name': displayName}).eq('id', id);
  }
}
