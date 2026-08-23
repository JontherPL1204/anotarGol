/// Rol dentro de un grupo. Espeja el enum `group_role` de Postgres.
enum GroupRole {
  groupAdmin,
  member;

  /// Como lo escribe Postgres.
  String get wire => this == groupAdmin ? 'group_admin' : 'member';

  static GroupRole parse(Object? value) =>
      value?.toString() == 'group_admin' ? groupAdmin : member;

  String get label => this == groupAdmin ? 'Administrador' : 'Miembro';

  /// Puede repartir claves de invitación y gestionar el grupo.
  bool get puedeInvitar => this == groupAdmin;
}

/// Una liga, torneo o comunidad. Tabla `public.groups`.
///
/// Es la frontera de privacidad de la app: si no perteneces a un grupo,
/// no ves nada de lo que pasa dentro.
class Grupo {
  const Grupo({
    required this.id,
    required this.name,
    this.slug,
    this.description,
    this.rol = GroupRole.member,
    this.equipos = 0,
    this.joinedAt,
  });

  final String id;
  final String name;
  final String? slug;
  final String? description;
  final GroupRole rol;

  /// Cuántos equipos tiene la liga.
  final int equipos;
  final DateTime? joinedAt;

  bool get puedeInvitar => rol.puedeInvitar;

  String get resumenEquipos => switch (equipos) {
        0 => 'Sin equipos todavía',
        1 => '1 equipo',
        _ => '$equipos equipos',
      };

  factory Grupo.fromMap(Map<String, dynamic> map) => Grupo(
        id: map['id'] as String,
        name: map['name'] as String,
        slug: map['slug'] as String?,
        description: map['description'] as String?,
        rol: GroupRole.parse(map['rol'] ?? map['role']),
        equipos: (map['equipos'] as num?)?.toInt() ?? 0,
        joinedAt: map['joined_at'] == null
            ? null
            : DateTime.parse(map['joined_at'] as String).toLocal(),
      );
}
