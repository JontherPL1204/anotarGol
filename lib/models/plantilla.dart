/// Cuánto le falta al equipo para poder jugar.
/// Vista `public.estado_plantilla`.
class EstadoPlantilla {
  const EstadoPlantilla({
    required this.teamId,
    this.equipo = '',
    this.jugadores = 0,
    this.conCedula = 0,
    this.yaRegistrados = 0,
    this.faltan = 11,
    this.habilitado = false,
    this.plantillaConfirmada = false,
  });

  final String teamId;
  final String equipo;

  /// Jugadores activos, con o sin cédula.
  final int jugadores;

  /// Los que cuentan para los 11 obligatorios.
  final int conCedula;

  /// Cuántos ya crearon su cuenta y reclamaron su ficha.
  final int yaRegistrados;

  final int faltan;

  /// Con 11 con cédula, el equipo puede retar y ser retado.
  final bool habilitado;

  /// El capitán ya revisó el armado inicial: se apagan los avisos de
  /// composición.
  final bool plantillaConfirmada;

  double get progreso => (conCedula / 11).clamp(0.0, 1.0);

  factory EstadoPlantilla.fromMap(Map<String, dynamic> map) => EstadoPlantilla(
        teamId: map['team_id'] as String,
        equipo: (map['equipo'] as String?) ?? '',
        jugadores: (map['jugadores'] as num?)?.toInt() ?? 0,
        conCedula: (map['con_cedula'] as num?)?.toInt() ?? 0,
        yaRegistrados: (map['ya_registrados'] as num?)?.toInt() ?? 0,
        faltan: (map['faltan'] as num?)?.toInt() ?? 11,
        habilitado: (map['habilitado'] as bool?) ?? false,
        plantillaConfirmada: (map['plantilla_confirmada'] as bool?) ?? false,
      );
}

/// Un aviso sobre la plantilla. Resultado de `avisos_de_plantilla()`.
///
/// La distinción importa: un `bloqueo` impide jugar, un `aviso` es una
/// observación que el capitán puede ignorar. Las posiciones repetidas
/// son avisos: es su decisión.
class AvisoPlantilla {
  const AvisoPlantilla({required this.tipo, required this.mensaje});

  final String tipo; // 'bloqueo' | 'aviso'
  final String mensaje;

  bool get esBloqueo => tipo == 'bloqueo';

  factory AvisoPlantilla.fromMap(Map<String, dynamic> map) => AvisoPlantilla(
        tipo: (map['tipo'] as String?) ?? 'aviso',
        mensaje: (map['mensaje'] as String?) ?? '',
      );
}

/// Un jugador encontrado por cédula, antes de sacarlo del equipo.
class JugadorBuscado {
  const JugadorBuscado({
    required this.id,
    required this.nombre,
    required this.cedula,
    this.dorsal,
    this.posicion = '',
    this.registrado = false,
    this.goles = 0,
  });

  final String id;
  final String nombre;
  final String cedula;
  final int? dorsal;
  final String posicion;

  /// Ya creó su cuenta y reclamó la ficha.
  final bool registrado;
  final int goles;

  factory JugadorBuscado.fromMap(Map<String, dynamic> map) => JugadorBuscado(
        id: map['id'] as String,
        nombre: map['full_name'] as String,
        cedula: (map['cedula'] as String?) ?? '',
        dorsal: (map['number'] as num?)?.toInt(),
        posicion: (map['posicion'] as String?) ?? '',
        registrado: (map['registrado'] as bool?) ?? false,
        goles: (map['goles'] as num?)?.toInt() ?? 0,
      );
}
