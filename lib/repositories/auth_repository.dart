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

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    String? displayName,
  }) =>
      _db.auth.signUp(
        email: email,
        password: password,
        data: displayName == null ? null : {'display_name': displayName},
      );

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
