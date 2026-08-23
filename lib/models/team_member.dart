import 'enums.dart';

/// Membresia de una persona en un equipo. Tabla `public.team_members`.
///
/// El rol vive aca y no en el usuario: la misma persona puede ser
/// entrenador de un club y simple hincha de otro.
class TeamMember {
  const TeamMember({
    required this.teamId,
    required this.userId,
    required this.role,
    this.displayName,
    this.email,
    this.avatarUrl,
  });

  final String teamId;
  final String userId;
  final TeamRole role;

  /// Vienen del join con `profiles` cuando se pide la lista del club.
  final String? displayName;
  final String? email;
  final String? avatarUrl;

  bool get canEdit => role.canEdit;
  bool get canAdmin => role.canAdmin;

  factory TeamMember.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'] as Map<String, dynamic>?;
    return TeamMember(
      teamId: map['team_id'] as String,
      userId: map['user_id'] as String,
      role: TeamRole.parse(map['role']),
      displayName: profile?['display_name'] as String?,
      email: profile?['email'] as String?,
      avatarUrl: profile?['avatar_url'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'team_id': teamId,
        'user_id': userId,
        'role': role.name,
      };
}
