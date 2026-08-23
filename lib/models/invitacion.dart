/// Clave de invitación a un grupo. Tabla `public.group_invites`.
///
/// El código son 8 caracteres en mayúscula sin `O`/`0` ni `I`/`1`, para
/// que se pueda dictar en voz alta sin que nadie lo escriba mal.
class Invitacion {
  const Invitacion({
    required this.id,
    required this.groupId,
    required this.code,
    this.maxUsos,
    this.usos = 0,
    this.expiresAt,
    this.isActive = true,
    this.createdAt,
  });

  final String id;
  final String groupId;
  final String code;

  /// `null` = sin límite de usos.
  final int? maxUsos;
  final int usos;

  /// `null` = no vence.
  final DateTime? expiresAt;
  final bool isActive;
  final DateTime? createdAt;

  bool get vencida =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  bool get agotada => maxUsos != null && usos >= maxUsos!;

  bool get vigente => isActive && !vencida && !agotada;

  /// Por qué no sirve, para poder decírselo al usuario.
  String get motivoNoVigente {
    if (!isActive) return 'Desactivada';
    if (vencida) return 'Vencida';
    if (agotada) return 'Agotada';
    return '';
  }

  String get resumenUsos =>
      maxUsos == null ? '$usos usos' : '$usos de $maxUsos usos';

  factory Invitacion.fromMap(Map<String, dynamic> map) => Invitacion(
        id: map['id'] as String,
        groupId: map['group_id'] as String,
        code: map['code'] as String,
        maxUsos: (map['max_uses'] as num?)?.toInt(),
        usos: (map['uses'] as num?)?.toInt() ?? 0,
        expiresAt: map['expires_at'] == null
            ? null
            : DateTime.parse(map['expires_at'] as String).toLocal(),
        isActive: (map['is_active'] as bool?) ?? true,
        createdAt: map['created_at'] == null
            ? null
            : DateTime.parse(map['created_at'] as String).toLocal(),
      );
}
