/// Qué es una clave de invitación, antes de canjearla.
/// Resultado de `revisar_clave()`.
class ClaveRevisada {
  const ClaveRevisada({
    required this.valida,
    this.motivo,
    this.tipo,
    this.descripcion,
    this.groupId,
    this.grupo,
    this.teamId,
    this.equipo,
  });

  final bool valida;

  /// Por qué no sirve, si no sirve.
  final String? motivo;

  /// 'admin' | 'capitan' | 'jugador' | 'equipo'
  final String? tipo;

  /// Qué le va a pasar a quien la canjee, ya redactado.
  final String? descripcion;

  final String? groupId;
  final String? grupo;
  final String? teamId;
  final String? equipo;

  /// Con esta clave vas a poder fundar tu equipo.
  bool get haceCapitan => tipo == 'capitan' || tipo == 'admin';

  /// Esta clave te suma a un equipo concreto.
  bool get llevaAEquipo => tipo == 'equipo';

  factory ClaveRevisada.fromMap(Map<String, dynamic> map) => ClaveRevisada(
        valida: (map['valida'] as bool?) ?? false,
        motivo: map['motivo'] as String?,
        tipo: map['tipo'] as String?,
        descripcion: map['descripcion'] as String?,
        groupId: map['group_id'] as String?,
        grupo: map['grupo'] as String?,
        teamId: map['team_id'] as String?,
        equipo: map['equipo'] as String?,
      );
}

/// Dónde quedó parado el usuario. Resultado de `mi_situacion()`.
///
/// Es lo que decide a qué pantalla llevarlo al arrancar: si no tiene
/// grupo va a la puerta; si es capitán sin equipo, a fundarlo; si tiene
/// equipo, al inicio.
class MiSituacion {
  const MiSituacion({
    this.tieneGrupo = false,
    this.tieneEquipo = false,
    this.puedeFundar = false,
    this.groupId,
    this.grupo,
    this.teamId,
    this.equipo,
    this.soyCapitan = false,
    this.tengoCedula = false,
  });

  final bool tieneGrupo;
  final bool tieneEquipo;
  final bool puedeFundar;
  final String? groupId;
  final String? grupo;
  final String? teamId;
  final String? equipo;
  final bool soyCapitan;
  final bool tengoCedula;

  /// Sin grupo no hay nada que mostrar: lo primero es la clave.
  bool get necesitaClave => !tieneGrupo;

  /// Entró con clave de capitán pero todavía no armó su equipo.
  bool get debeFundarEquipo => tieneGrupo && !tieneEquipo && puedeFundar;

  /// Está en la liga pero nadie lo fichó y no puede fundar.
  bool get esperaQueLoFichen => tieneGrupo && !tieneEquipo && !puedeFundar;

  factory MiSituacion.fromMap(Map<String, dynamic> map) => MiSituacion(
        tieneGrupo: (map['tiene_grupo'] as bool?) ?? false,
        tieneEquipo: (map['tiene_equipo'] as bool?) ?? false,
        puedeFundar: (map['puede_fundar'] as bool?) ?? false,
        groupId: map['group_id'] as String?,
        grupo: map['grupo'] as String?,
        teamId: map['team_id'] as String?,
        equipo: map['equipo'] as String?,
        soyCapitan: (map['soy_capitan'] as bool?) ?? false,
        tengoCedula: (map['tengo_cedula'] as bool?) ?? false,
      );
}
