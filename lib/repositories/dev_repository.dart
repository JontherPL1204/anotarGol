import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_service.dart';
import '../models/models.dart';

/// El panel de desarrollo.
///
/// Nada de esto devuelve datos a quien no sea dev: las vistas están
/// filtradas por `dev_panel_abierto()` en la propia base, así que si el
/// panel está cerrado llegan listas vacías en vez de un error.
class DevRepository {
  const DevRepository();

  SupabaseClient get _db => SupabaseService.client;

  /// Una fila con todo lo que la app necesita para decidir qué mostrar.
  Future<PanelDev> estado() async {
    final filas = await _db.rpc('mi_panel_dev');
    final lista = filas as List;
    if (lista.isEmpty) return const PanelDev();
    return PanelDev.fromMap(Map<String, dynamic>.from(lista.first as Map));
  }

  /// Canjear una clave de acceso: convierte la cuenta en dev.
  ///
  /// Devuelve el motivo en vez de lanzar cuando la clave es incorrecta.
  Future<ResultadoClave> canjearClaveDev(String codigo) async {
    final filas = await _db.rpc('canjear_clave_dev', params: {
      'p_codigo': codigo.trim(),
    });
    final lista = filas as List;
    if (lista.isEmpty) {
      return const ResultadoClave(ok: false, motivo: 'No hubo respuesta.');
    }
    return ResultadoClave.fromMap(Map<String, dynamic>.from(lista.first as Map));
  }

  /// Abrir el panel de quien ya es dev.
  Future<ResultadoClave> abrirPanel({String? codigo, int minutos = 30}) async {
    final filas = await _db.rpc('dev_abrir_panel', params: {
      'p_codigo': codigo ?? '',
      'p_minutos': minutos,
    });
    final lista = filas as List;
    if (lista.isEmpty) {
      return const ResultadoClave(ok: false, motivo: 'No hubo respuesta.');
    }
    return ResultadoClave.fromMap(Map<String, dynamic>.from(lista.first as Map));
  }

  Future<void> cerrarPanel() => _db.rpc('dev_cerrar_panel');

  // -------------------------------------------------------------------
  // Ligas
  // -------------------------------------------------------------------

  Future<List<GrupoDev>> ligas() async {
    final filas = await _db.from('panel_dev_grupos').select().order('name');
    return filas.map(GrupoDev.fromMap).toList();
  }

  /// Sin nombre, la liga nace como "La Liga A", B, C...
  Future<void> crearLiga({String? nombre, String? descripcion}) =>
      _db.rpc('crear_grupo', params: {
        'p_nombre': nombre,
        'p_descripcion': descripcion,
      });

  Future<void> renombrarLiga({required String groupId, required String nombre}) =>
      _db.rpc('renombrar_liga', params: {
        'p_group_id': groupId,
        'p_nombre': nombre,
      });

  /// Borra la liga con todo lo que cuelga de ella. Queda en la bitácora.
  Future<void> borrarLiga(String groupId) =>
      _db.rpc('dev_borrar_grupo', params: {'p_group_id': groupId});

  /// La clave que se le entrega a un capitán para que funde su equipo.
  Future<String> claveDeCapitan({
    required String groupId,
    int? maxUsos = 1,
    int? dias,
  }) async {
    final fila = await _db.rpc('crear_invitacion', params: {
      'p_group_id': groupId,
      'p_max_usos': maxUsos,
      'p_dias': dias,
      'p_para_capitan': true,
      'p_para_admin': false,
    });
    return Map<String, dynamic>.from(fila as Map)['code'] as String;
  }

  // -------------------------------------------------------------------
  // Equipos
  // -------------------------------------------------------------------

  Future<List<EquipoDev>> equipos({String? groupId}) async {
    var q = _db.from('panel_dev_equipos').select();
    if (groupId != null) q = q.eq('group_id', groupId);
    final filas = await q.order('numero');
    return filas.map(EquipoDev.fromMap).toList();
  }

  Future<void> borrarEquipo(String teamId) =>
      _db.rpc('dev_borrar_equipo', params: {'p_team_id': teamId});

  // -------------------------------------------------------------------
  // Claves de acceso y quién es dev
  // -------------------------------------------------------------------

  Future<List<ClaveDev>> claves() async {
    final filas =
        await _db.from('dev_claves_resumen').select().order('created_at', ascending: false);
    return filas.map(ClaveDev.fromMap).toList();
  }

  /// Crea una clave que convierte en dev a quien la canjee.
  ///
  /// Por defecto de un solo uso: sirve para dar de alta a alguien y deja
  /// de servir. Una llave maestra permanente sería lo peor de los dos
  /// mundos.
  Future<void> crearClaveDev({
    required String codigo,
    int maxUsos = 1,
    int? dias,
    String? nota,
  }) =>
      _db.rpc('crear_clave_dev', params: {
        'p_codigo': codigo,
        'p_max_usos': maxUsos,
        'p_dias': dias,
        'p_nota': nota,
      });

  Future<void> revocarClave(String id) =>
      _db.rpc('revocar_clave_dev', params: {'p_id': id});

  Future<List<DevActivo>> devs() async {
    final filas = await _db.from('devs_activos').select().order('created_at');
    return filas.map(DevActivo.fromMap).toList();
  }

  Future<void> quitarDev(String userId) =>
      _db.rpc('quitar_dev', params: {'p_user_id': userId});

  /// Devolver el propio acceso.
  Future<void> renunciar() => _db.rpc('renunciar_a_dev');
}
