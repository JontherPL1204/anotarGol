import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_service.dart';
import '../models/models.dart';

/// Partidos: calendario, historial y marcador en vivo.
///
/// Las lecturas usan la vista `match_summary` (trae local/visitante y el
/// resultado ya resueltos); las escrituras van contra la tabla `matches`.
class MatchesRepository {
  const MatchesRepository();

  SupabaseClient get _db => SupabaseService.client;

  /// El proximo partido: reemplaza el texto fijo de la pantalla de inicio.
  Future<FootballMatch?> fetchNext(String teamId) async {
    final row = await _db
        .from('match_summary')
        .select()
        .eq('team_id', teamId)
        .inFilter('status', ['scheduled', 'live'])
        .gte('kickoff_at', DateTime.now()
            .subtract(const Duration(hours: 3))
            .toUtc()
            .toIso8601String())
        .order('kickoff_at', ascending: true)
        .limit(1)
        .maybeSingle();

    return row == null ? null : FootballMatch.fromMap(row);
  }

  /// El ultimo partido jugado, para mostrar "ultimo resultado".
  Future<FootballMatch?> fetchLastPlayed(String teamId) async {
    final row = await _db
        .from('match_summary')
        .select()
        .eq('team_id', teamId)
        .eq('status', 'finished')
        .order('kickoff_at', ascending: false)
        .limit(1)
        .maybeSingle();

    return row == null ? null : FootballMatch.fromMap(row);
  }

  /// El partido que se esta jugando ahora, si hay alguno.
  /// El partido del día con su reloj y su fase, desde `partido_en_vivo`.
  ///
  /// Devuelve tambien los que aun no empiezan: saber que falta media hora
  /// es parte de poder empezarlo a tiempo.
  Future<PartidoVivo?> partidoDelDia(String teamId) async {
    final filas = await _db
        .from('partido_en_vivo')
        .select()
        .eq('team_id', teamId)
        .order('kickoff_at', ascending: true)
        .limit(1);
    if (filas.isEmpty) return null;
    return PartidoVivo.fromMap(Map<String, dynamic>.from(filas.first));
  }

  /// Arranca el reloj. Es lo unico que pone el partido en `live`, y sin
  /// eso la base no acepta ni un gol ni una tarjeta (migracion 45).
  Future<void> iniciar(String matchId) =>
      _db.rpc('iniciar_partido', params: {'p_match_id': matchId});

  Future<void> irAlDescanso(String matchId) =>
      _db.rpc('ir_al_descanso', params: {'p_match_id': matchId});

  Future<void> iniciarSegundoTiempo(String matchId) =>
      _db.rpc('iniciar_segundo_tiempo', params: {'p_match_id': matchId});

  Future<void> finalizar(String matchId, {int agregados = 0}) =>
      _db.rpc('finalizar_partido', params: {
        'p_match_id': matchId,
        'p_agregados': agregados,
      });

  Future<FootballMatch?> fetchLive(String teamId) async {
    final row = await _db
        .from('match_summary')
        .select()
        .eq('team_id', teamId)
        .eq('status', 'live')
        .order('kickoff_at', ascending: false)
        .limit(1)
        .maybeSingle();

    return row == null ? null : FootballMatch.fromMap(row);
  }

  Future<List<FootballMatch>> fetchByTeam(
    String teamId, {
    String? seasonId,
    MatchStatus? status,
    int limit = 50,
  }) async {
    var query = _db.from('match_summary').select().eq('team_id', teamId);
    if (seasonId != null) query = query.eq('season_id', seasonId);
    if (status != null) query = query.eq('status', status.name);

    final rows = await query.order('kickoff_at', ascending: false).limit(limit);
    return rows.map(FootballMatch.fromMap).toList();
  }

  Future<FootballMatch> create(FootballMatch match) async {
    final row = await _db
        .from('matches')
        .insert({
          ...match.toMap(),
          'created_by': SupabaseService.currentUser?.id,
        })
        .select()
        .single();
    return FootballMatch.fromMap(row);
  }

  Future<FootballMatch> update(FootballMatch match) async {
    final row = await _db
        .from('matches')
        .update(match.toMap())
        .eq('id', match.id)
        .select()
        .single();
    return FootballMatch.fromMap(row);
  }

  /// Arranca, pausa o cierra un partido. El marcador no se toca aca:
  /// lo mantiene el trigger a partir de los eventos.
  Future<void> setStatus(String matchId, MatchStatus status) =>
      _db.from('matches').update({'status': status.name}).eq('id', matchId);

  Future<void> delete(String matchId) =>
      _db.from('matches').delete().eq('id', matchId);

  /// Marcador en vivo. Esto es lo que hace real la frase "Seguimiento en
  /// vivo del partido" que ya esta en el banner de la app: el hincha ve
  /// el gol en cuanto el DT lo registra en otro dispositivo.
  ///
  /// Nota: Realtime solo funciona sobre tablas, no sobre vistas, asi que
  /// aca se escucha `matches` (sin `team_name` ni `result`).
  Stream<FootballMatch?> watchMatch(String matchId) => _db
      .from('matches')
      .stream(primaryKey: ['id'])
      .eq('id', matchId)
      .map((rows) => rows.isEmpty ? null : FootballMatch.fromMap(rows.first));
}
