/// En qué momento está el partido. Lo calcula la vista `partido_en_vivo`
/// a partir del reloj, no lo decide la app.
enum FasePartido {
  /// Todavía falta para la hora acordada.
  esperando,

  /// Media hora antes del pitazo: ya se puede arrancar.
  listoParaEmpezar,
  primerTiempo,
  descanso,
  segundoTiempo,
  terminado;

  static FasePartido parse(Object? valor) => switch (valor) {
        'listo_para_empezar' => FasePartido.listoParaEmpezar,
        'primer_tiempo' => FasePartido.primerTiempo,
        'descanso' => FasePartido.descanso,
        'segundo_tiempo' => FasePartido.segundoTiempo,
        'terminado' => FasePartido.terminado,
        _ => FasePartido.esperando,
      };

  String get label => switch (this) {
        FasePartido.esperando => 'Aún no empieza',
        FasePartido.listoParaEmpezar => 'Listo para empezar',
        FasePartido.primerTiempo => 'Primer tiempo',
        FasePartido.descanso => 'Descanso',
        FasePartido.segundoTiempo => 'Segundo tiempo',
        FasePartido.terminado => 'Terminado',
      };

  /// Con el partido rodando se cantan goles y se sacan tarjetas.
  bool get enJuego =>
      this == FasePartido.primerTiempo || this == FasePartido.segundoTiempo;
}

/// El partido con su reloj. Fila de la vista `partido_en_vivo`.
class PartidoVivo {
  const PartidoVivo({
    required this.id,
    required this.teamId,
    required this.equipo,
    required this.fase,
    required this.kickoffAt,
    this.rival,
    this.opponentTeamId,
    this.golesPropios = 0,
    this.golesRival = 0,
    this.minuto,
    this.venue,
    this.minutos = 90,
    this.cambios = 5,
  });

  final String id;
  final String teamId;
  final String equipo;
  final String? rival;
  final String? opponentTeamId;
  final FasePartido fase;
  final DateTime kickoffAt;
  final int golesPropios;
  final int golesRival;

  /// Minuto de juego. `null` mientras el partido no ha arrancado.
  final int? minuto;

  final String? venue;
  final int minutos;
  final int cambios;

  bool get enJuego => fase.enJuego;

  /// El marcador tal como se dice en voz alta.
  String get marcador => '$golesPropios - $golesRival';

  factory PartidoVivo.fromMap(Map<String, dynamic> map) => PartidoVivo(
        id: map['id'] as String,
        teamId: map['team_id'] as String,
        equipo: (map['equipo'] as String?) ?? 'Tu equipo',
        rival: map['rival'] as String?,
        opponentTeamId: map['opponent_team_id'] as String?,
        fase: FasePartido.parse(map['fase']),
        kickoffAt: DateTime.parse(map['kickoff_at'] as String).toLocal(),
        golesPropios: (map['team_score'] as num?)?.toInt() ?? 0,
        golesRival: (map['opponent_score'] as num?)?.toInt() ?? 0,
        minuto: (map['minuto'] as num?)?.toInt(),
        venue: map['venue'] as String?,
        minutos: (map['duration_minutes'] as num?)?.toInt() ?? 90,
        cambios: (map['substitutions_allowed'] as num?)?.toInt() ?? 5,
      );
}
