/// Un equipo contrario registrado por el club. Tabla `public.rivals`.
class Rival {
  const Rival({
    required this.id,
    required this.teamId,
    required this.name,
    this.logoUrl,
    this.notes,
    this.totalJugadores = 0,
    this.totalImaginarios = 0,
  });

  final String id;
  final String teamId;
  final String name;
  final String? logoUrl;
  final String? notes;

  /// Vienen del conteo cuando se pide la lista de rivales.
  final int totalJugadores;
  final int totalImaginarios;

  /// true si toda la plantilla cargada es inventada.
  bool get plantillaEsInventada =>
      totalJugadores > 0 && totalImaginarios == totalJugadores;

  bool get sinPlantilla => totalJugadores == 0;

  factory Rival.fromMap(Map<String, dynamic> map) => Rival(
        id: map['id'] as String,
        teamId: map['team_id'] as String,
        name: map['name'] as String,
        logoUrl: map['logo_url'] as String?,
        notes: map['notes'] as String?,
        totalJugadores: (map['total_jugadores'] as num?)?.toInt() ?? 0,
        totalImaginarios: (map['total_imaginarios'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'team_id': teamId,
        'name': name,
        'logo_url': logoUrl,
        'notes': notes,
      };
}
