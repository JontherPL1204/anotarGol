import 'enums.dart';

/// Fila del ranking de goleadores. Vista `public.goleadores`.
class Goleador {
  const Goleador({
    required this.jugadorId,
    required this.nombre,
    required this.goles,
    this.dorsal,
    this.position = PlayerPosition.mf,
    this.esDelClub = true,
    this.esImaginario = false,
    this.club,
  });

  final String jugadorId;
  final String nombre;
  final int goles;
  final int? dorsal;
  final PlayerPosition position;

  /// `false` si el goleador es de un equipo rival.
  final bool esDelClub;

  /// `true` si el jugador fue inventado por falta de datos del rival.
  final bool esImaginario;

  /// Nombre del club rival. Null para los nuestros.
  final String? club;

  String get dorsalLabel => dorsal?.toString() ?? '-';

  factory Goleador.fromMap(Map<String, dynamic> map) => Goleador(
        jugadorId: map['jugador_id'] as String,
        nombre: map['nombre'] as String,
        goles: (map['goles'] as num?)?.toInt() ?? 0,
        dorsal: (map['dorsal'] as num?)?.toInt(),
        position: PlayerPosition.parse(map['position']),
        esDelClub: map['bando'] == 'nuestro',
        esImaginario: (map['es_imaginario'] as bool?) ?? false,
        club: map['club'] as String?,
      );
}
