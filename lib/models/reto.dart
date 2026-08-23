/// Un reto entre dos capitanes.
///
/// La misma fila se mira desde los dos lados: para quien lo mandó es
/// "retaste a X", para quien lo recibe es "X te retó". Por eso hay un
/// solo modelo y un `soyRetador`, en vez de dos listas separadas.
class Reto {
  const Reto({
    required this.id,
    required this.soyRetador,
    required this.otroEquipoId,
    required this.otroEquipo,
    required this.estado,
    required this.cuando,
    this.otroLogo,
    this.mensaje,
    this.lugar,
    this.minutos = 90,
    this.cambios = 5,
    this.matchId,
    this.chocaConTuAgenda = false,
  });

  final String id;

  /// `true` si mi equipo mandó el reto; `false` si lo recibió.
  final bool soyRetador;

  final String otroEquipoId;
  final String otroEquipo;
  final String? otroLogo;

  /// `pending`, `accepted`, `rejected`, `cancelled`, `expired`, `played`.
  final String estado;

  final DateTime cuando;
  final String? mensaje;
  final String? lugar;
  final int minutos;
  final int cambios;

  /// El partido que nació de este reto, si ya se acordó.
  final String? matchId;

  /// Aviso, no bloqueo: el capitán decide, pero informado.
  final bool chocaConTuAgenda;

  bool get pendiente => estado == 'pending';

  /// Solo el equipo retado responde, y solo mientras esté pendiente.
  bool get puedoResponder => pendiente && !soyRetador;

  String get estadoLegible => switch (estado) {
        'pending' => soyRetador ? 'Esperando respuesta' : 'Te están retando',
        'accepted' => 'Aceptado',
        'rejected' => 'Rechazado',
        'cancelled' => 'Cancelado',
        'expired' => 'Venció',
        'played' => 'Jugado',
        _ => estado,
      };

  factory Reto.fromMap(Map<String, dynamic> map) => Reto(
        id: map['id'] as String,
        soyRetador: (map['soy_retador'] as bool?) ?? false,
        otroEquipoId: map['otro_equipo_id'] as String,
        otroEquipo: (map['otro_equipo'] as String?) ?? 'Equipo',
        otroLogo: map['otro_logo'] as String?,
        estado: (map['status'] as String?) ?? 'pending',
        cuando: DateTime.parse(map['proposed_kickoff_at'] as String).toLocal(),
        mensaje: map['message'] as String?,
        lugar: map['venue'] as String?,
        minutos: (map['duration_minutes'] as num?)?.toInt() ?? 90,
        cambios: (map['substitutions_allowed'] as num?)?.toInt() ?? 5,
        matchId: map['match_id'] as String?,
        chocaConTuAgenda: (map['choca_con_tu_agenda'] as bool?) ?? false,
      );
}
