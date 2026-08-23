import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_service.dart';
import '../models/models.dart';

/// Eventos del partido: goles, tarjetas y cambios.
///
/// El marcador NUNCA se escribe desde aca. Se registra el evento y un
/// trigger de la base recalcula `matches.team_score` / `opponent_score`.
/// Asi el marcador y el historial no pueden contradecirse.
class MatchEventsRepository {
  const MatchEventsRepository();

  SupabaseClient get _db => SupabaseService.client;

  Future<List<MatchEvent>> fetchByMatch(String matchId) async {
    final rows = await _db
        .from('match_events')
        .select()
        .eq('match_id', matchId)
        .order('minute', ascending: true, nullsFirst: false)
        .order('created_at', ascending: true);
    return rows.map(MatchEvent.fromMap).toList();
  }

  /// El equivalente persistido del boton "!CANTAR GOL!".
  ///
  /// [playerId] puede ir en null para anotar rapido durante el partido y
  /// asignar el autor despues.
  Future<MatchEvent> logGoal({
    required String matchId,
    String? playerId,
    String? rivalPlayerId,
    String? assistPlayerId,
    int? minute,
    TeamSide side = TeamSide.us,
    bool isOwnGoal = false,
  }) async {
    final row = await _db.rpc('log_goal', params: {
      'p_match_id': matchId,
      'p_player_id': playerId,
      'p_minute': minute,
      'p_side': side.name,
      'p_assist_player_id': assistPlayerId,
      'p_is_own_goal': isOwnGoal,
      'p_rival_player_id': rivalPlayerId,
    });
    return MatchEvent.fromMap(Map<String, dynamic>.from(row as Map));
  }

  /// Tarjeta amarilla o roja.
  ///
  /// Va por `log_tarjeta` y no por un insert suelto, para que pase por
  /// las mismas comprobaciones que el gol: el partido tiene que estar en
  /// juego, y el minuto lo pone el reloj de la base.
  Future<MatchEvent> logTarjeta({
    required String matchId,
    required MatchEventType type,
    String? playerId,
    String? rivalPlayerId,
    TeamSide side = TeamSide.us,
    int? minute,
  }) async {
    final row = await _db.rpc('log_tarjeta', params: {
      'p_match_id': matchId,
      'p_tipo': type.wire,
      'p_player_id': playerId,
      'p_side': side.name,
      'p_rival_player_id': rivalPlayerId,
      'p_minute': minute,
    });
    return MatchEvent.fromMap(Map<String, dynamic>.from(row as Map));
  }

  Future<MatchEvent> add(MatchEvent event) async {
    final row = await _db
        .from('match_events')
        .insert({
          ...event.toMap(),
          'created_by': SupabaseService.currentUser?.id,
        })
        .select()
        .single();
    return MatchEvent.fromMap(row);
  }

  /// Corrige un gol mal cargado. El marcador se ajusta solo.
  Future<MatchEvent> update(MatchEvent event) async {
    final row = await _db
        .from('match_events')
        .update(event.toMap())
        .eq('id', event.id)
        .select()
        .single();
    return MatchEvent.fromMap(row);
  }

  /// Deshacer un gol. Equivale al boton de reiniciar, pero fino.
  Future<void> delete(String eventId) =>
      _db.from('match_events').delete().eq('id', eventId);

  /// Reinicia el marcador borrando todos los goles del partido.
  /// Es el reemplazo honesto de `_reiniciarMarcador()`: sin esto, poner
  /// el marcador en 0 dejaria goles huerfanos en el historial.
  Future<void> clearGoals(String matchId) => _db
      .from('match_events')
      .delete()
      .eq('match_id', matchId)
      .eq('type', 'goal');

  /// Narracion en vivo del partido.
  Stream<List<MatchEvent>> watchByMatch(String matchId) => _db
      .from('match_events')
      .stream(primaryKey: ['id'])
      .eq('match_id', matchId)
      .order('minute')
      .map((rows) => rows.map(MatchEvent.fromMap).toList());
}
