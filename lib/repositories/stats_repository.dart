import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_service.dart';
import '../models/models.dart';

/// Estadisticas. Todo el calculo ocurre en Postgres (vista
/// `player_stats`): la app pide una fila por jugador en lugar de
/// descargar todos los eventos para contarlos en el celular.
class StatsRepository {
  const StatsRepository();

  SupabaseClient get _db => SupabaseService.client;

  Future<List<PlayerStats>> fetchTeamStats(
    String teamId, {
    bool onlyActive = true,
  }) async {
    var query = _db.from('player_stats').select().eq('team_id', teamId);
    if (onlyActive) query = query.eq('is_active', true);

    final rows = await query.order('goals', ascending: false);
    return rows.map(PlayerStats.fromMap).toList();
  }

  /// Tabla de goleadores del club.
  Future<List<PlayerStats>> fetchTopScorers(String teamId, {int limit = 10}) async {
    final rows = await _db
        .from('player_stats')
        .select()
        .eq('team_id', teamId)
        .gt('goals', 0)
        .order('goals', ascending: false)
        .limit(limit);
    return rows.map(PlayerStats.fromMap).toList();
  }

  Future<PlayerStats?> fetchPlayerStats(String playerId) async {
    final row = await _db
        .from('player_stats')
        .select()
        .eq('player_id', playerId)
        .maybeSingle();
    return row == null ? null : PlayerStats.fromMap(row);
  }

  /// Balance del club: partidos ganados, empatados y perdidos.
  Future<({int played, int won, int drawn, int lost, int goalsFor, int goalsAgainst})>
      fetchTeamRecord(String teamId, {String? seasonId}) async {
    var query = _db
        .from('match_summary')
        .select('result, team_score, opponent_score')
        .eq('team_id', teamId)
        .eq('status', 'finished');
    if (seasonId != null) query = query.eq('season_id', seasonId);

    final rows = await query;

    var won = 0, drawn = 0, lost = 0, goalsFor = 0, goalsAgainst = 0;
    for (final row in rows) {
      final result = row['result'];
      if (result == 'W') {
        won++;
      } else if (result == 'D') {
        drawn++;
      } else if (result == 'L') {
        lost++;
      }
      goalsFor += (row['team_score'] as num?)?.toInt() ?? 0;
      goalsAgainst += (row['opponent_score'] as num?)?.toInt() ?? 0;
    }

    return (
      played: rows.length,
      won: won,
      drawn: drawn,
      lost: lost,
      goalsFor: goalsFor,
      goalsAgainst: goalsAgainst,
    );
  }
}
