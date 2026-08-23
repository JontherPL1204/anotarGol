import '../core/app_env.dart';
import '../core/supabase_service.dart';
import '../models/models.dart';
import '../repositories/repositories.dart';

/// Todo lo que se escribe y lo que solo tiene sentido con backend:
/// editar la plantilla, gestionar equipos rivales y leer los rankings.
///
/// Va aparte de [ClubDataSource] a proposito. Esa fuente tiene que
/// funcionar tambien sin servidor (modo demo), mientras que esto solo
/// existe cuando hay base: no se puede "guardar un jugador" en el aire.
///
/// Es una clase concreta y no una interfaz porque las pruebas la
/// extienden y sustituyen los metodos que necesitan.
class ClubAdmin {
  const ClubAdmin({
    this.teamIdOverride,
    this.players = const PlayersRepository(),
    this.rivals = const RivalsRepository(),
    this.stats = const StatsRepository(),
  });

  /// Club sobre el que se opera. Si es null se usa el de `AppEnv`.
  final String? teamIdOverride;
  final PlayersRepository players;
  final RivalsRepository rivals;
  final StatsRepository stats;

  String get teamId => teamIdOverride ?? AppEnv.defaultTeamId;

  /// `false` sin backend: las pantallas de edicion deben decirlo en vez
  /// de ofrecer botones que no van a guardar nada.
  bool get disponible => SupabaseService.isReady;

  // -------------------------------------------------------------------
  // Plantilla propia
  // -------------------------------------------------------------------

  Future<List<Player>> jugadores() => players.fetchByTeam(teamId);

  Future<Player> crearJugador({
    required String nombre,
    int? dorsal,
    PlayerPosition posicion = PlayerPosition.mf,
    String? detallePosicion,
  }) =>
      players.create(
        teamId: teamId,
        fullName: nombre,
        number: dorsal,
        position: posicion,
        positionDetail: detallePosicion,
      );

  Future<Player> actualizarJugador(Player jugador) => players.update(jugador);

  /// Baja logica: conserva los goles del jugador en el historial.
  Future<void> darDeBaja(String jugadorId) => players.deactivate(jugadorId);

  // -------------------------------------------------------------------
  // Equipos rivales
  // -------------------------------------------------------------------

  Future<List<Rival>> equiposRivales() => rivals.fetchByTeam(teamId);

  /// Registra un rival. Con [inventarPlantilla] en true le genera 11
  /// jugadores ficticios, marcados como tales.
  Future<Rival> crearRival({
    required String nombre,
    bool inventarPlantilla = true,
    int cantidad = 11,
  }) =>
      rivals.crearRivalConPlantilla(
        teamId: teamId,
        nombre: nombre,
        inventarPlantilla: inventarPlantilla,
        cantidad: cantidad,
      );

  Future<void> eliminarRival(String rivalId) => rivals.eliminar(rivalId);

  Future<List<RivalPlayer>> jugadoresRivales(String rivalId) =>
      rivals.fetchPlayers(rivalId);

  /// Vuelve a inventar la plantilla. Respeta a los jugadores reales que
  /// alguien haya cargado a mano.
  Future<List<RivalPlayer>> generarPlantillaImaginaria(
    String rivalId, {
    int cantidad = 11,
  }) =>
      rivals.generarPlantillaImaginaria(rivalId, cantidad: cantidad);

  Future<RivalPlayer> agregarJugadorRival({
    required String rivalId,
    required String nombre,
    int? dorsal,
    PlayerPosition posicion = PlayerPosition.mf,
    String? detallePosicion,
  }) =>
      rivals.agregarJugador(
        rivalId: rivalId,
        teamId: teamId,
        fullName: nombre,
        number: dorsal,
        position: posicion,
        positionDetail: detallePosicion,
      );

  Future<RivalPlayer> actualizarJugadorRival(RivalPlayer jugador) =>
      rivals.actualizarJugador(jugador);

  Future<void> eliminarJugadorRival(String jugadorId) =>
      rivals.eliminarJugador(jugadorId);

  // -------------------------------------------------------------------
  // Rankings
  // -------------------------------------------------------------------

  Future<List<Goleador>> goleadores({bool soloDelClub = false}) =>
      stats.fetchGoleadores(teamId, soloDelClub: soloDelClub);

  Future<List<GolHistorial>> historialDeGoles() =>
      stats.fetchHistorialGoles(teamId);
}
