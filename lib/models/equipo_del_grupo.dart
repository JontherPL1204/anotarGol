/// Fila de `equipos_del_grupo()`: un equipo de la liga, visto desde
/// fuera. Es lo que se usa para elegir a quién retar.
class EquipoDelGrupo {
  const EquipoDelGrupo({
    required this.id,
    required this.name,
    this.shortName,
    this.logoUrl,
    this.primaryColorHex = '#1B5E20',
    this.jugadores = 0,
    this.tieneCapitan = false,
    this.esMiEquipo = false,
  });

  final String id;
  final String name;
  final String? shortName;
  final String? logoUrl;
  final String primaryColorHex;
  final int jugadores;

  /// Sin capitán no hay a quién retar.
  final bool tieneCapitan;
  final bool esMiEquipo;

  bool get sePuedeRetar => tieneCapitan && !esMiEquipo;

  factory EquipoDelGrupo.fromMap(Map<String, dynamic> map) => EquipoDelGrupo(
        id: map['id'] as String,
        name: map['name'] as String,
        shortName: map['short_name'] as String?,
        logoUrl: map['logo_url'] as String?,
        primaryColorHex: (map['primary_color'] as String?) ?? '#1B5E20',
        jugadores: (map['jugadores'] as num?)?.toInt() ?? 0,
        tieneCapitan: (map['tiene_capitan'] as bool?) ?? false,
        esMiEquipo: (map['es_mi_equipo'] as bool?) ?? false,
      );
}

/// Fila de la vista `tabla_del_grupo`: posiciones de la liga.
class PosicionTabla {
  const PosicionTabla({
    required this.equipoId,
    required this.equipo,
    this.jugados = 0,
    this.ganados = 0,
    this.empatados = 0,
    this.perdidos = 0,
    this.golesAFavor = 0,
    this.golesEnContra = 0,
    this.puntos = 0,
  });

  final String equipoId;
  final String equipo;
  final int jugados;
  final int ganados;
  final int empatados;
  final int perdidos;
  final int golesAFavor;
  final int golesEnContra;
  final int puntos;

  int get diferencia => golesAFavor - golesEnContra;

  factory PosicionTabla.fromMap(Map<String, dynamic> map) => PosicionTabla(
        equipoId: map['equipo_id'] as String,
        equipo: map['equipo'] as String,
        jugados: (map['jugados'] as num?)?.toInt() ?? 0,
        ganados: (map['ganados'] as num?)?.toInt() ?? 0,
        empatados: (map['empatados'] as num?)?.toInt() ?? 0,
        perdidos: (map['perdidos'] as num?)?.toInt() ?? 0,
        golesAFavor: (map['goles_a_favor'] as num?)?.toInt() ?? 0,
        golesEnContra: (map['goles_en_contra'] as num?)?.toInt() ?? 0,
        puntos: (map['puntos'] as num?)?.toInt() ?? 0,
      );
}
