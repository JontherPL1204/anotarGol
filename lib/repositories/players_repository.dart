import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_service.dart';
import '../models/models.dart';

/// La plantilla, ahora persistida.
///
/// Sustituye la lista fija de `lib/plantilla.dart`.
class PlayersRepository {
  const PlayersRepository();

  SupabaseClient get _db => SupabaseService.client;

  /// Plantilla ordenada por dorsal. Los sin numero van al final.
  Future<List<Player>> fetchByTeam(
    String teamId, {
    bool onlyActive = true,
  }) async {
    var query = _db.from('players').select().eq('team_id', teamId);
    if (onlyActive) query = query.eq('is_active', true);

    final rows = await query.order('number', ascending: true, nullsFirst: false);
    return rows.map(Player.fromMap).toList();
  }

  Future<Player?> fetchById(String playerId) async {
    final row =
        await _db.from('players').select().eq('id', playerId).maybeSingle();
    return row == null ? null : Player.fromMap(row);
  }

  Future<Player> create({
    required String teamId,
    required String fullName,
    int? number,
    PlayerPosition position = PlayerPosition.mf,
    String? positionDetail,
  }) async {
    final row = await _db
        .from('players')
        .insert({
          'team_id': teamId,
          'full_name': fullName,
          'number': number,
          'position': position.wire,
          'position_detail': positionDetail,
        })
        .select()
        .single();
    return Player.fromMap(row);
  }

  Future<Player> update(Player player) async {
    final row = await _db
        .from('players')
        .update(player.toMap())
        .eq('id', player.id)
        .select()
        .single();
    return Player.fromMap(row);
  }

  /// Baja logica: conserva goles e historial del jugador.
  /// Al quedar inactivo libera el dorsal para otro jugador.
  Future<void> deactivate(String playerId) =>
      _db.from('players').update({'is_active': false}).eq('id', playerId);

  /// Borrado real. Los eventos del jugador quedan sin autor
  /// (`player_id` pasa a null) en vez de desaparecer.
  Future<void> delete(String playerId) =>
      _db.from('players').delete().eq('id', playerId);

  /// Plantilla en vivo: se actualiza sola si otro dispositivo la edita.
  Stream<List<Player>> watchByTeam(String teamId) => _db
      .from('players')
      .stream(primaryKey: ['id'])
      .eq('team_id', teamId)
      .map((rows) => rows.map(Player.fromMap).toList()
        ..sort((a, b) => (a.number ?? 999).compareTo(b.number ?? 999)));
}
