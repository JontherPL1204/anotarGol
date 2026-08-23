/// Estado del panel de desarrollo. Resultado de `mi_panel_dev()`.
class PanelDev {
  const PanelDev({
    this.soyDev = false,
    this.hayClave = false,
    this.abierto = false,
    this.expiraAt,
    this.bloqueadoHasta,
    this.intentos = 0,
  });

  final bool soyDev;

  /// Si hay una clave de panel definida. Sin ella, basta con ser dev.
  final bool hayClave;
  final bool abierto;
  final DateTime? expiraAt;

  /// Tras cinco intentos fallidos, el acceso se bloquea un rato.
  final DateTime? bloqueadoHasta;
  final int intentos;

  bool get bloqueado =>
      bloqueadoHasta != null && bloqueadoHasta!.isAfter(DateTime.now());

  Duration? get restante {
    final e = expiraAt;
    if (!abierto || e == null) return null;
    final d = e.difference(DateTime.now());
    return d.isNegative ? null : d;
  }

  factory PanelDev.fromMap(Map<String, dynamic> map) => PanelDev(
        soyDev: (map['soy_dev'] as bool?) ?? false,
        hayClave: (map['hay_clave'] as bool?) ?? false,
        abierto: (map['abierto'] as bool?) ?? false,
        expiraAt: map['expira_at'] == null
            ? null
            : DateTime.parse(map['expira_at'] as String).toLocal(),
        bloqueadoHasta: map['bloqueado_hasta'] == null
            ? null
            : DateTime.parse(map['bloqueado_hasta'] as String).toLocal(),
        intentos: (map['intentos'] as num?)?.toInt() ?? 0,
      );
}

/// Lo que devuelve canjear una clave o abrir el panel.
///
/// No lanza excepción ante una clave incorrecta: devuelve el motivo. Eso
/// es lo que permite que el contador de intentos sobreviva, porque una
/// excepción abortaría la transacción y desharía el registro.
class ResultadoClave {
  const ResultadoClave({required this.ok, this.motivo, this.expira});

  final bool ok;
  final String? motivo;
  final DateTime? expira;

  factory ResultadoClave.fromMap(Map<String, dynamic> map) => ResultadoClave(
        ok: (map['ok'] as bool?) ?? false,
        motivo: map['motivo'] as String?,
        expira: map['expira'] == null
            ? null
            : DateTime.parse(map['expira'] as String).toLocal(),
      );
}

/// Una liga vista desde el panel. Vista `panel_dev_grupos`.
class GrupoDev {
  const GrupoDev({
    required this.id,
    required this.name,
    this.equipos = 0,
    this.miembros = 0,
    this.invitacionesActivas = 0,
    this.partidos = 0,
  });

  final String id;
  final String name;
  final int equipos;
  final int miembros;
  final int invitacionesActivas;
  final int partidos;

  factory GrupoDev.fromMap(Map<String, dynamic> map) => GrupoDev(
        id: map['id'] as String,
        name: map['name'] as String,
        equipos: (map['equipos'] as num?)?.toInt() ?? 0,
        miembros: (map['miembros'] as num?)?.toInt() ?? 0,
        invitacionesActivas: (map['invitaciones_activas'] as num?)?.toInt() ?? 0,
        partidos: (map['partidos'] as num?)?.toInt() ?? 0,
      );
}

/// Un equipo visto desde el panel. Vista `panel_dev_equipos`.
///
/// [etiqueta] ya viene con el formato del dev: "Equipo 1 (Halcones FC)".
class EquipoDev {
  const EquipoDev({
    required this.id,
    required this.groupId,
    required this.etiqueta,
    this.numero,
    this.nombre = '',
    this.logoUrl,
    this.jugadores = 0,
    this.conCedula = 0,
    this.miembros = 0,
    this.tieneCapitan = false,
    this.habilitado = false,
    this.plantillaConfirmada = false,
  });

  final String id;
  final String groupId;
  final String etiqueta;
  final int? numero;
  final String nombre;
  final String? logoUrl;
  final int jugadores;
  final int conCedula;
  final int miembros;
  final bool tieneCapitan;
  final bool habilitado;
  final bool plantillaConfirmada;

  int get faltan => (11 - conCedula).clamp(0, 11);

  factory EquipoDev.fromMap(Map<String, dynamic> map) => EquipoDev(
        id: map['id'] as String,
        groupId: map['group_id'] as String,
        etiqueta: (map['etiqueta'] as String?) ?? '',
        numero: (map['numero'] as num?)?.toInt(),
        nombre: (map['nombre'] as String?) ?? '',
        logoUrl: map['logo_url'] as String?,
        jugadores: (map['jugadores'] as num?)?.toInt() ?? 0,
        conCedula: (map['con_cedula'] as num?)?.toInt() ?? 0,
        miembros: (map['miembros'] as num?)?.toInt() ?? 0,
        tieneCapitan: (map['tiene_capitan'] as bool?) ?? false,
        habilitado: (map['habilitado'] as bool?) ?? false,
        plantillaConfirmada: (map['plantilla_confirmada'] as bool?) ?? false,
      );
}

/// Una clave de acceso de dev, sin revelar el código.
class ClaveDev {
  const ClaveDev({
    required this.id,
    this.pista = '',
    this.maxUsos = 1,
    this.usos = 0,
    this.expiresAt,
    this.isActive = true,
    this.nota,
    this.vigente = false,
  });

  final String id;

  /// Los tres primeros caracteres y el resto en asteriscos.
  final String pista;
  final int maxUsos;
  final int usos;
  final DateTime? expiresAt;
  final bool isActive;
  final String? nota;
  final bool vigente;

  String get resumen => '$usos de $maxUsos usos';

  factory ClaveDev.fromMap(Map<String, dynamic> map) => ClaveDev(
        id: map['id'] as String,
        pista: (map['pista'] as String?) ?? '',
        maxUsos: (map['max_usos'] as num?)?.toInt() ?? 1,
        usos: (map['usos'] as num?)?.toInt() ?? 0,
        expiresAt: map['expires_at'] == null
            ? null
            : DateTime.parse(map['expires_at'] as String).toLocal(),
        isActive: (map['is_active'] as bool?) ?? true,
        nota: map['nota'] as String?,
        vigente: (map['vigente'] as bool?) ?? false,
      );
}

/// Quién tiene acceso de dev. Vista `devs_activos`.
class DevActivo {
  const DevActivo({
    required this.userId,
    this.email,
    this.nombre,
    this.nota,
    this.soyYo = false,
  });

  final String userId;
  final String? email;
  final String? nombre;
  final String? nota;
  final bool soyYo;

  factory DevActivo.fromMap(Map<String, dynamic> map) => DevActivo(
        userId: map['user_id'] as String,
        email: map['email'] as String?,
        nombre: map['display_name'] as String?,
        nota: map['note'] as String?,
        soyYo: (map['soy_yo'] as bool?) ?? false,
      );
}
