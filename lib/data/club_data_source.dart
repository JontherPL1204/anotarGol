import '../core/app_env.dart';
import '../core/supabase_service.dart';
import '../models/models.dart';
import '../repositories/repositories.dart';
import 'demo_club.dart';

/// De donde salen los datos que ve la interfaz.
///
/// Existe para que las pantallas no tengan que preguntarse si hay
/// backend. Hay dos implementaciones:
///
///   * [LocalClubDataSource]   - datos de ejemplo, sin red. Es lo que se
///     usa si no hay credenciales de Supabase, y lo que hace que la app
///     siga arrancando en clase o en una demo sin internet.
///   * [SupabaseClubDataSource] - la base real.
///
/// Las pruebas inyectan la suya y no tocan red.
abstract class ClubDataSource {
  /// `true` si los datos vienen de la base y por tanto se pueden editar
  /// de forma que los vean otros dispositivos.
  bool get isRemote;

  Future<List<Player>> fetchPlayers();

  /// El proximo partido, o el que se esta jugando ahora.
  Future<FootballMatch?> fetchNextMatch();

  /// El partido en vivo, si hay uno. `null` si no.
  Future<FootballMatch?> fetchLiveMatch();

  Future<List<MatchEvent>> fetchEvents(String matchId);

  /// Registra un gol. Devuelve el partido con el marcador ya actualizado.
  Future<FootballMatch?> logGoal(String matchId);

  /// Borra los goles del partido (el "reiniciar marcador" honesto).
  Future<void> clearGoals(String matchId);

  /// Marcador en vivo. En local emite una sola vez y se queda quieto.
  Stream<FootballMatch?> watchMatch(String matchId);

  /// Elige la fuente segun haya backend o no.
  static ClubDataSource resolve() => SupabaseService.isReady
      ? const SupabaseClubDataSource()
      : const LocalClubDataSource();
}

/// Datos de ejemplo. No escribe nada en ningun lado.
class LocalClubDataSource implements ClubDataSource {
  const LocalClubDataSource();

  @override
  bool get isRemote => false;

  @override
  Future<List<Player>> fetchPlayers() async => DemoClub.players;

  @override
  Future<FootballMatch?> fetchNextMatch() async => DemoClub.nextMatch();

  /// Sin backend no hay partido en vivo: el marcador funciona como
  /// contador local, igual que en la primera version de la app.
  @override
  Future<FootballMatch?> fetchLiveMatch() async => null;

  @override
  Future<List<MatchEvent>> fetchEvents(String matchId) async => const [];

  @override
  Future<FootballMatch?> logGoal(String matchId) async => null;

  @override
  Future<void> clearGoals(String matchId) async {}

  @override
  Stream<FootballMatch?> watchMatch(String matchId) => Stream.value(null);
}

/// La base real. Delega en los repositorios; no habla con Supabase directo.
class SupabaseClubDataSource implements ClubDataSource {
  const SupabaseClubDataSource({
    this.teamId = AppEnv.defaultTeamId,
    this.players = const PlayersRepository(),
    this.matches = const MatchesRepository(),
    this.events = const MatchEventsRepository(),
  });

  final String teamId;
  final PlayersRepository players;
  final MatchesRepository matches;
  final MatchEventsRepository events;

  @override
  bool get isRemote => true;

  @override
  Future<List<Player>> fetchPlayers() => players.fetchByTeam(teamId);

  @override
  Future<FootballMatch?> fetchNextMatch() => matches.fetchNext(teamId);

  @override
  Future<FootballMatch?> fetchLiveMatch() => matches.fetchLive(teamId);

  @override
  Future<List<MatchEvent>> fetchEvents(String matchId) =>
      events.fetchByMatch(matchId);

  @override
  Future<FootballMatch?> logGoal(String matchId) async {
    // Solo se registra el evento: el marcador lo recalcula un trigger de
    // Postgres, asi que hay que volver a leer el partido para verlo.
    await events.logGoal(matchId: matchId);
    return matches.fetchLive(teamId);
  }

  @override
  Future<void> clearGoals(String matchId) => events.clearGoals(matchId);

  @override
  Stream<FootballMatch?> watchMatch(String matchId) =>
      matches.watchMatch(matchId);
}
