import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException, AuthState, User;

import '../models/models.dart';
import '../repositories/repositories.dart';
import 'app_env.dart';
import 'supabase_service.dart';

/// Quien esta usando la app y que puede hacer.
///
/// Es un [ChangeNotifier] a proposito: la sesion es el unico estado que
/// de verdad comparten varias pantallas, y para eso alcanza lo que ya
/// trae Flutter. El plan pedia no meter Provider ni Riverpod hasta tener
/// una necesidad real, y esto no la justifica.
///
/// Los metodos devuelven `String?` en vez de lanzar excepciones: `null`
/// es exito y cualquier otra cosa es un mensaje ya listo para mostrar.
/// Asi las pantallas no tienen que atrapar errores de Supabase.
class Session extends ChangeNotifier {
  Session({
    String? teamId,
    this.auth = const AuthRepository(),
    this.teams = const TeamsRepository(),
  }) : teamId = teamId ?? AppEnv.defaultTeamId;

  final String teamId;
  final AuthRepository auth;
  final TeamsRepository teams;

  StreamSubscription<AuthState>? _suscripcion;
  User? _usuario;
  TeamRole? _rol;
  bool _ocupado = false;

  /// `false` si la app corre sin backend. Todo lo demas se apaga solo.
  bool get hayBackend => SupabaseService.isReady;

  User? get usuario => _usuario;
  TeamRole? get rol => _rol;
  bool get haySesion => _usuario != null;
  bool get ocupado => _ocupado;

  /// Puede registrar goles, jugadores y partidos.
  bool get puedeEditar => _rol?.canEdit ?? false;

  /// Puede gestionar miembros y ajustes del club.
  bool get puedeAdministrar => _rol?.canAdmin ?? false;

  /// Puede editar la plantilla (nombres, dorsales, posiciones) y los
  /// equipos rivales. Cualquier integrante del club, no solo el staff.
  bool get puedeEditarPlantilla => _rol?.canEditSquad ?? false;

  String get nombre {
    final meta = _usuario?.userMetadata?['display_name'];
    if (meta is String && meta.trim().isNotEmpty) return meta.trim();
    final correo = _usuario?.email;
    if (correo != null && correo.isNotEmpty) return correo.split('@').first;
    return 'Invitado';
  }

  String get rolLegible => switch (_rol) {
        TeamRole.owner => 'Dueño del club',
        TeamRole.admin => 'Administrador',
        TeamRole.coach => 'Cuerpo técnico',
        TeamRole.player => 'Jugador',
        TeamRole.viewer => 'Hincha',
        null => 'Sin rol en este club',
      };

  /// Se llama una vez desde `main()`. Nunca lanza: si el backend falla,
  /// la app sigue funcionando como invitado.
  Future<void> iniciar() async {
    if (!hayBackend) return;

    _usuario = auth.currentUser;
    await _cargarRol();

    _suscripcion = auth.onAuthStateChange.listen((estado) async {
      _usuario = estado.session?.user;
      await _cargarRol();
    });
  }

  Future<void> _cargarRol() async {
    try {
      _rol = _usuario == null ? null : await teams.myRole(teamId);
    } catch (_) {
      _rol = null;
    }
    notifyListeners();
  }

  Future<String?> entrar({
    required String correo,
    required String clave,
  }) =>
      _intentar(() => auth.signIn(email: correo, password: clave));

  Future<String?> registrarse({
    required String correo,
    required String clave,
    String? nombreVisible,
  }) =>
      _intentar(() => auth.signUp(
            email: correo,
            password: clave,
            displayName: nombreVisible,
          ));

  Future<void> salir() async {
    if (!hayBackend) return;
    try {
      await auth.signOut();
    } catch (_) {
      // Aunque el servidor no conteste, localmente ya no hay sesion.
    }
    _usuario = null;
    _rol = null;
    notifyListeners();
  }

  /// Toma el club si todavia no tiene dueño. Es el paso que convierte a
  /// la primera persona registrada en `owner` (ver `claim_team` en la
  /// migracion 02).
  Future<String?> reclamarClub() => _intentar(() async {
        await teams.claimTeam(teamId);
      });

  Future<String?> _intentar(Future<void> Function() accion) async {
    if (!hayBackend) {
      return 'La app está en modo local: no hay servidor configurado.';
    }

    _ocupado = true;
    notifyListeners();
    try {
      await accion();
      await _cargarRol();
      return null;
    } on AuthException catch (e) {
      return _traducir(e.message);
    } catch (e) {
      return _traducir(e.toString());
    } finally {
      _ocupado = false;
      notifyListeners();
    }
  }

  /// Supabase responde en inglés; esto lo deja presentable.
  static String _traducir(String mensaje) {
    final m = mensaje.toLowerCase();
    if (m.contains('invalid login credentials')) {
      return 'Correo o contraseña incorrectos.';
    }
    if (m.contains('user already registered')) {
      return 'Ese correo ya tiene una cuenta. Inicia sesión.';
    }
    if (m.contains('password should be at least')) {
      return 'La contraseña es muy corta: usa al menos 6 caracteres.';
    }
    if (m.contains('unable to validate email') || m.contains('invalid email')) {
      return 'Ese correo no parece válido.';
    }
    if (m.contains('email not confirmed')) {
      return 'Tienes que confirmar el correo antes de entrar.';
    }
    if (m.contains('ya tiene un owner')) {
      return 'Este club ya tiene dueño. Pídele que te invite.';
    }
    if (m.contains('failed host lookup') || m.contains('socketexception')) {
      return 'Sin conexión. Revisa tu internet.';
    }
    return 'No se pudo completar la operación. Inténtalo de nuevo.';
  }

  @override
  void dispose() {
    _suscripcion?.cancel();
    super.dispose();
  }
}
