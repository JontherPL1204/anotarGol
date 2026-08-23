import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_service.dart';
import '../models/models.dart';

/// Lo que hace un capitán con su equipo: fundarlo, ponerle nombre y
/// escudo, cargar los 11 por cédula y confirmar la plantilla.
class CapitanRepository {
  const CapitanRepository();

  SupabaseClient get _db => SupabaseService.client;

  // -------------------------------------------------------------------
  // Fundar y dar identidad
  // -------------------------------------------------------------------

  /// Funda el equipo dentro de la liga. Quien lo crea queda como dueño
  /// y capitán: lo hace un trigger de la base, no hace falta un paso más.
  Future<Team> fundarEquipo({
    required String groupId,
    required String nombre,
    String? nombreCorto,
  }) async {
    final fila = await _db.rpc('create_team', params: {
      'p_name': nombre,
      'p_short_name': nombreCorto,
      'p_primary_color': '#1B5E20',
      'p_secondary_color': '#FFD700',
      'p_is_public': false,
      'p_group_id': groupId,
    });
    return Team.fromMap(Map<String, dynamic>.from(fila as Map));
  }

  /// El nombre es obligatorio; el escudo, opcional.
  ///
  /// Pasar [logoUrl] en null deja el escudo como estaba; pasar cadena
  /// vacía lo quita.
  Future<Team> actualizarIdentidad({
    required String teamId,
    required String nombre,
    String? nombreCorto,
    String? logoUrl,
  }) async {
    final fila = await _db.rpc('actualizar_identidad_equipo', params: {
      'p_team_id': teamId,
      'p_nombre': nombre,
      'p_short_name': nombreCorto,
      'p_logo_url': logoUrl,
    });
    return Team.fromMap(Map<String, dynamic>.from(fila as Map));
  }

  /// Sube el escudo al bucket `team-logos`.
  ///
  /// El archivo va bajo la carpeta del equipo porque es lo que exigen
  /// las políticas de storage: la primera carpeta de la ruta identifica
  /// al club y decide quién puede escribir ahí.
  Future<String> subirEscudo({
    required String teamId,
    required Uint8List bytes,
    required String extension,
  }) async {
    final ruta = '$teamId/escudo.$extension';

    await _db.storage.from('team-logos').uploadBinary(
          ruta,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );

    // Se le agrega la marca de tiempo para que al reemplazar el escudo
    // la caché del dispositivo no siga mostrando el anterior.
    final url = _db.storage.from('team-logos').getPublicUrl(ruta);
    return '$url?v=${DateTime.now().millisecondsSinceEpoch}';
  }

  // -------------------------------------------------------------------
  // Los 11 obligatorios
  // -------------------------------------------------------------------

  Future<EstadoPlantilla?> estadoPlantilla(String teamId) async {
    final fila = await _db
        .from('estado_plantilla')
        .select()
        .eq('team_id', teamId)
        .maybeSingle();
    return fila == null ? null : EstadoPlantilla.fromMap(fila);
  }

  /// Bloqueos y avisos. Los de composición solo aparecen mientras el
  /// capitán arma el equipo.
  Future<List<AvisoPlantilla>> avisos(String teamId) async {
    final filas = await _db.rpc('avisos_de_plantilla', params: {
      'p_team_id': teamId,
    });
    return (filas as List)
        .map((f) => AvisoPlantilla.fromMap(Map<String, dynamic>.from(f as Map)))
        .toList();
  }

  /// Ficha a un jugador. La cédula es su identidad: cuando esa persona
  /// cree su cuenta con ella, recibirá esta ficha automáticamente.
  Future<Player> ficharJugador({
    required String teamId,
    required String cedula,
    required String nombre,
    int? dorsal,
    PlayerPosition posicion = PlayerPosition.mf,
    String? detallePosicion,
  }) async {
    final fila = await _db
        .from('players')
        .insert({
          'team_id': teamId,
          'cedula': cedula.trim(),
          'full_name': nombre.trim(),
          'number': dorsal,
          'position': posicion.wire,
          'position_detail': detallePosicion,
        })
        .select()
        .single();
    return Player.fromMap(fila);
  }

  /// Busca por cédula antes de sacar a alguien, para que la confirmación
  /// pueda decir a quién se va a sacar.
  Future<JugadorBuscado?> buscarPorCedula({
    required String teamId,
    required String cedula,
  }) async {
    final filas = await _db.rpc('buscar_jugador_por_cedula', params: {
      'p_team_id': teamId,
      'p_cedula': cedula.trim(),
    });
    final lista = filas as List;
    if (lista.isEmpty) return null;
    return JugadorBuscado.fromMap(Map<String, dynamic>.from(lista.first as Map));
  }

  /// Baja lógica: los goles del jugador se quedan en el historial.
  Future<void> sacarPorCedula({
    required String teamId,
    required String cedula,
  }) =>
      _db.rpc('sacar_jugador_por_cedula', params: {
        'p_team_id': teamId,
        'p_cedula': cedula.trim(),
      });

  /// Cierra el armado inicial. A partir de aquí dejan de salir los
  /// avisos de composición: un club con 20 fichados va a tener cuatro
  /// laterales derechos y está bien.
  Future<void> confirmarPlantilla(String teamId) =>
      _db.rpc('confirmar_plantilla', params: {'p_team_id': teamId});

  Future<void> reabrirPlantilla(String teamId) =>
      _db.rpc('reabrir_plantilla', params: {'p_team_id': teamId});

  // -------------------------------------------------------------------
  // La clave que reparte a su gente
  // -------------------------------------------------------------------

  Future<String> crearClaveDeEquipo({
    required String teamId,
    TeamRole rol = TeamRole.player,
    int? maxUsos,
    int? dias,
  }) async {
    final fila = await _db.rpc('crear_invitacion_equipo', params: {
      'p_team_id': teamId,
      'p_rol': rol.name,
      'p_max_usos': maxUsos,
      'p_dias': dias,
    });
    return Map<String, dynamic>.from(fila as Map)['code'] as String;
  }
}
