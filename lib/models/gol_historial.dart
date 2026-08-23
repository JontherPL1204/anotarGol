/// Un gol del historial. Vista `public.historial_goles`.
class GolHistorial {
  const GolHistorial({
    required this.id,
    required this.matchId,
    required this.goleador,
    required this.esNuestro,
    required this.rival,
    required this.fecha,
    this.minuto,
    this.dorsal,
    this.asistencia,
    this.esImaginario = false,
    this.esAutogol = false,
  });

  final String id;
  final String matchId;

  /// Puede venir vacio: se permite anotar un gol rapido sin decir quien.
  final String goleador;
  final bool esNuestro;
  final String rival;
  final DateTime fecha;
  final int? minuto;
  final int? dorsal;
  final String? asistencia;
  final bool esImaginario;
  final bool esAutogol;

  String get minutoLabel => minuto == null ? '' : "$minuto'";

  factory GolHistorial.fromMap(Map<String, dynamic> map) => GolHistorial(
        id: map['id'] as String,
        matchId: map['match_id'] as String,
        goleador: (map['goleador'] as String?) ?? 'Sin autor registrado',
        esNuestro: map['side'] == 'us',
        rival: (map['opponent_name'] as String?) ?? 'Rival',
        fecha: DateTime.parse(map['kickoff_at'] as String).toLocal(),
        minuto: (map['minute'] as num?)?.toInt(),
        dorsal: (map['dorsal'] as num?)?.toInt(),
        asistencia: map['asistencia'] as String?,
        esImaginario: (map['es_imaginario'] as bool?) ?? false,
        esAutogol: (map['is_own_goal'] as bool?) ?? false,
      );
}
