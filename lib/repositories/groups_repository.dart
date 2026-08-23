import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_service.dart';
import '../models/models.dart';

/// Grupos (ligas) e invitaciones.
///
/// El grupo es la frontera de privacidad de la app: una cuenta que no
/// pertenece a ninguno no ve absolutamente nada. Por eso canjear una
/// clave de invitación es el primer paso real después de registrarse.
class GroupsRepository {
  const GroupsRepository();

  SupabaseClient get _db => SupabaseService.client;

  /// Los grupos a los que perteneces, con tu rol en cada uno. Es lo que
  /// alimenta el selector de grupo del perfil.
  Future<List<Grupo>> misGrupos() async {
    final filas = await _db.rpc('mis_grupos');
    return (filas as List)
        .map((f) => Grupo.fromMap(Map<String, dynamic>.from(f as Map)))
        .toList();
  }

  /// Crea la liga y te deja como administrador. Genera además la primera
  /// clave de invitación, porque un grupo sin invitación no sirve.
  Future<Grupo> crearGrupo({
    required String nombre,
    String? descripcion,
  }) async {
    final fila = await _db.rpc('crear_grupo', params: {
      'p_nombre': nombre,
      'p_descripcion': descripcion,
    });
    return Grupo.fromMap(Map<String, dynamic>.from(fila as Map));
  }

  /// Qué hace una clave, sin gastarla. Es lo que permite confirmarle al
  /// usuario qué le va a pasar antes de canjear.
  Future<ClaveRevisada> revisarClave(String codigo) async {
    final filas = await _db.rpc('revisar_clave', params: {
      'p_codigo': codigo.trim().toUpperCase(),
    });
    final lista = filas as List;
    if (lista.isEmpty) {
      return const ClaveRevisada(valida: false, motivo: 'Esa clave no existe.');
    }
    return ClaveRevisada.fromMap(Map<String, dynamic>.from(lista.first as Map));
  }

  /// Canjea la clave sea del tipo que sea: de liga o de equipo. Quien
  /// recibe un código por WhatsApp no tiene por qué saber cuál es.
  Future<Map<String, dynamic>> canjearClave(String codigo) async {
    final filas = await _db.rpc('canjear_clave', params: {
      'p_codigo': codigo.trim().toUpperCase(),
    });
    final lista = filas as List;
    if (lista.isEmpty) throw StateError('La clave no devolvió resultado');
    return Map<String, dynamic>.from(lista.first as Map);
  }

  /// Dónde quedó parado el usuario, para decidir a qué pantalla va.
  Future<MiSituacion> miSituacion() async {
    final filas = await _db.rpc('mi_situacion');
    final lista = filas as List;
    if (lista.isEmpty) return const MiSituacion();
    return MiSituacion.fromMap(Map<String, dynamic>.from(lista.first as Map));
  }

  /// Canjea una clave de grupo. Devuelve el grupo al que acabas de entrar.
  ///
  /// Volver a canjear la misma clave no gasta un uso ni duplica nada:
  /// la función de Postgres lo contempla.
  Future<Grupo> unirseConCodigo(String codigo) async {
    final fila = await _db.rpc('unirse_con_codigo', params: {
      'p_codigo': codigo.trim().toUpperCase(),
    });
    return Grupo.fromMap(Map<String, dynamic>.from(fila as Map));
  }

  /// Solo el administrador del grupo las ve.
  Future<List<Invitacion>> invitaciones(String groupId) async {
    final filas = await _db
        .from('group_invites')
        .select()
        .eq('group_id', groupId)
        .order('created_at', ascending: false);
    return filas.map(Invitacion.fromMap).toList();
  }

  /// [maxUsos] y [dias] en null significan sin límite y sin vencimiento.
  Future<Invitacion> crearInvitacion({
    required String groupId,
    int? maxUsos,
    int? dias,
  }) async {
    final fila = await _db.rpc('crear_invitacion', params: {
      'p_group_id': groupId,
      'p_max_usos': maxUsos,
      'p_dias': dias,
    });
    return Invitacion.fromMap(Map<String, dynamic>.from(fila as Map));
  }

  /// No se borra: se desactiva, para no perder el rastro de quién entró
  /// con ella.
  Future<void> desactivarInvitacion(String invitacionId) => _db
      .from('group_invites')
      .update({'is_active': false}).eq('id', invitacionId);

  /// Los equipos de la liga. Devuelve vacío si no perteneces al grupo.
  Future<List<EquipoDelGrupo>> equiposDelGrupo(String groupId) async {
    final filas = await _db.rpc('equipos_del_grupo', params: {
      'p_group_id': groupId,
    });
    return (filas as List)
        .map((f) => EquipoDelGrupo.fromMap(Map<String, dynamic>.from(f as Map)))
        .toList();
  }

  /// Tabla de posiciones, ya ordenada como se ordena una liga.
  Future<List<PosicionTabla>> tablaDelGrupo(String groupId) async {
    final filas = await _db
        .from('tabla_del_grupo')
        .select()
        .eq('group_id', groupId)
        .order('puntos', ascending: false)
        .order('diferencia', ascending: false)
        .order('goles_a_favor', ascending: false);
    return filas.map(PosicionTabla.fromMap).toList();
  }

  /// Salirse de un grupo.
  Future<void> salirDelGrupo(String groupId) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    await _db
        .from('group_members')
        .delete()
        .eq('group_id', groupId)
        .eq('user_id', user.id);
  }
}
