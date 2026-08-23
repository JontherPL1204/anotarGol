import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_service.dart';
import '../models/models.dart';

/// Equipos contrarios y sus jugadores.
///
/// El caso que resuelve: vas a jugar contra un equipo del que no sabes ni
/// los nombres. En vez de dejar la pantalla vacia, [crearRivalConPlantilla]
/// arma un 4-3-3 inventado y lo marca como tal.
class RivalsRepository {
  const RivalsRepository();

  SupabaseClient get _db => SupabaseService.client;

  /// Rivales del club, con el conteo de jugadores cargados.
  Future<List<Rival>> fetchByTeam(String teamId) async {
    final rows = await _db
        .from('rivals')
        .select('*, rival_players(id, is_imaginary)')
        .eq('team_id', teamId)
        .order('name');

    return rows.map((row) {
      final jugadores = (row['rival_players'] as List?) ?? const [];
      return Rival.fromMap({
        ...row,
        'total_jugadores': jugadores.length,
        'total_imaginarios':
            jugadores.where((j) => j['is_imaginary'] == true).length,
      });
    }).toList();
  }

  Future<Rival?> fetchById(String rivalId) async {
    final row = await _db.from('rivals').select().eq('id', rivalId).maybeSingle();
    return row == null ? null : Rival.fromMap(row);
  }

  /// Crea el rival. Si [inventarPlantilla] es true, le genera 11
  /// jugadores ficticios en el mismo paso.
  Future<Rival> crearRivalConPlantilla({
    required String teamId,
    required String nombre,
    bool inventarPlantilla = true,
    int cantidad = 11,
  }) async {
    final row = await _db.rpc('crear_rival_con_plantilla', params: {
      'p_team_id': teamId,
      'p_nombre': nombre,
      'p_inventar': inventarPlantilla,
      'p_cantidad': cantidad,
    });
    return Rival.fromMap(Map<String, dynamic>.from(row as Map));
  }

  Future<void> renombrar(String rivalId, String nombre) =>
      _db.from('rivals').update({'name': nombre}).eq('id', rivalId);

  Future<void> eliminar(String rivalId) =>
      _db.from('rivals').delete().eq('id', rivalId);

  // -------------------------------------------------------------------
  // Jugadores del rival
  // -------------------------------------------------------------------

  Future<List<RivalPlayer>> fetchPlayers(String rivalId) async {
    final rows = await _db
        .from('rival_players')
        .select()
        .eq('rival_id', rivalId)
        .eq('is_active', true)
        .order('number', ascending: true, nullsFirst: false);
    return rows.map(RivalPlayer.fromMap).toList();
  }

  /// (Re)genera la plantilla ficticia.
  ///
  /// Los jugadores reales cargados a mano NO se tocan: la funcion de
  /// Postgres solo borra los que tienen `is_imaginary = true`.
  Future<List<RivalPlayer>> generarPlantillaImaginaria(
    String rivalId, {
    int cantidad = 11,
  }) async {
    final rows = await _db.rpc('generar_plantilla_imaginaria', params: {
      'p_rival_id': rivalId,
      'p_cantidad': cantidad,
    });
    return (rows as List)
        .map((r) => RivalPlayer.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<RivalPlayer> agregarJugador({
    required String rivalId,
    required String teamId,
    required String fullName,
    int? number,
    PlayerPosition position = PlayerPosition.mf,
    String? positionDetail,
  }) async {
    final row = await _db
        .from('rival_players')
        .insert({
          'rival_id': rivalId,
          'team_id': teamId,
          'full_name': fullName,
          'number': number,
          'position': position.wire,
          'position_detail': positionDetail,
          // Cargado a mano = dato real.
          'is_imaginary': false,
        })
        .select()
        .single();
    return RivalPlayer.fromMap(row);
  }

  /// Al editar a mano un jugador inventado deja de serlo: alguien puso
  /// el dato real.
  Future<RivalPlayer> actualizarJugador(RivalPlayer jugador) async {
    final row = await _db
        .from('rival_players')
        .update({...jugador.toMap(), 'is_imaginary': false})
        .eq('id', jugador.id)
        .select()
        .single();
    return RivalPlayer.fromMap(row);
  }

  Future<void> eliminarJugador(String jugadorId) =>
      _db.from('rival_players').delete().eq('id', jugadorId);
}
