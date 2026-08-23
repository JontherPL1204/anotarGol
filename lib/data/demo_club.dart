import '../models/models.dart';

/// Datos de ejemplo del club.
///
/// Son los mismos que inserta `supabase/seed.sql` (mismos UUID incluidos),
/// para que la app se vea igual con backend y sin el.
///
/// Antes vivian dentro de los widgets: los 11 jugadores en
/// `plantilla.dart` y el proximo partido como texto fijo en
/// `homescreen.dart`. Tenerlos en un solo lugar es lo que permite
/// cambiarlos por datos reales sin tocar la interfaz.
class DemoClub {
  const DemoClub._();

  static const String teamId = 'a0000000-0000-4000-8000-000000000001';
  static const String teamName = 'Pasión Futbolera FC';

  static const List<Player> players = [
    Player(id: 'b0000000-0000-4000-8000-000000000001', teamId: teamId, number: 1, fullName: 'Carlos Navas', position: PlayerPosition.gk, positionDetail: 'Portero'),
    Player(id: 'b0000000-0000-4000-8000-000000000002', teamId: teamId, number: 2, fullName: 'Luis Paredes', position: PlayerPosition.df, positionDetail: 'Defensa Central'),
    Player(id: 'b0000000-0000-4000-8000-000000000003', teamId: teamId, number: 3, fullName: 'Mateo Torres', position: PlayerPosition.df, positionDetail: 'Defensa Central'),
    Player(id: 'b0000000-0000-4000-8000-000000000004', teamId: teamId, number: 4, fullName: 'Jorge Caicedo', position: PlayerPosition.df, positionDetail: 'Lateral Derecho'),
    Player(id: 'b0000000-0000-4000-8000-000000000006', teamId: teamId, number: 5, fullName: 'Sebastián Méndez', position: PlayerPosition.mf, positionDetail: 'Mediocampista Defensivo'),
    Player(id: 'b0000000-0000-4000-8000-000000000005', teamId: teamId, number: 6, fullName: 'Felipe Valencia', position: PlayerPosition.df, positionDetail: 'Lateral Izquierdo'),
    Player(id: 'b0000000-0000-4000-8000-000000000009', teamId: teamId, number: 7, fullName: 'Javier Rodríguez', position: PlayerPosition.fw, positionDetail: 'Extremo Derecho'),
    Player(id: 'b0000000-0000-4000-8000-000000000007', teamId: teamId, number: 8, fullName: 'Andrés Gómez', position: PlayerPosition.mf, positionDetail: 'Mediocampista Central'),
    Player(id: 'b0000000-0000-4000-8000-000000000011', teamId: teamId, number: 9, fullName: 'Ronny Benítez', position: PlayerPosition.fw, positionDetail: 'Delantero Centro'),
    Player(id: 'b0000000-0000-4000-8000-000000000008', teamId: teamId, number: 10, fullName: 'Diego López', position: PlayerPosition.mf, positionDetail: 'Mediocampista Ofensivo'),
    Player(id: 'b0000000-0000-4000-8000-000000000010', teamId: teamId, number: 11, fullName: 'Gabriel Mina', position: PlayerPosition.fw, positionDetail: 'Extremo Izquierdo'),
  ];

  /// El proximo domingo a las 16:00, igual que en el seed.
  static DateTime nextSunday16([DateTime? desde]) {
    final hoy = desde ?? DateTime.now();
    final diasHastaDomingo = hoy.weekday == DateTime.sunday ? 7 : 7 - hoy.weekday;
    final domingo = DateTime(hoy.year, hoy.month, hoy.day + diasHastaDomingo);
    return DateTime(domingo.year, domingo.month, domingo.day, 16);
  }

  static FootballMatch nextMatch([DateTime? desde]) => FootballMatch(
        id: 'd0000000-0000-4000-8000-000000000002',
        teamId: teamId,
        teamName: teamName,
        opponentName: 'Clásicos FC',
        kickoffAt: nextSunday16(desde),
        venue: 'Cancha del Club',
        competition: 'Liga Barrial',
      );
}
