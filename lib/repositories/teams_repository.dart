import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_service.dart';
import '../models/models.dart';

/// Acceso al club y a sus miembros.
class TeamsRepository {
  const TeamsRepository();

  SupabaseClient get _db => SupabaseService.client;

  /// Un equipo por id. Devuelve null si no existe o si es privado y no
  /// pertenezco a el (RLS lo filtra, no da error).
  Future<Team?> fetchById(String teamId) async {
    final row = await _db.from('teams').select().eq('id', teamId).maybeSingle();
    return row == null ? null : Team.fromMap(row);
  }

  /// Un equipo por su slug publico (util para compartir por enlace).
  Future<Team?> fetchBySlug(String slug) async {
    final row = await _db.from('teams').select().eq('slug', slug).maybeSingle();
    return row == null ? null : Team.fromMap(row);
  }

  /// Equipos donde soy miembro, con mi rol en cada uno.
  Future<List<(Team, TeamRole)>> fetchMyTeams() async {
    final user = SupabaseService.currentUser;
    if (user == null) return const [];

    final rows = await _db
        .from('team_members')
        .select('role, teams!inner(*)')
        .eq('user_id', user.id);

    return rows
        .map((row) => (
              Team.fromMap(row['teams'] as Map<String, dynamic>),
              TeamRole.parse(row['role']),
            ))
        .toList();
  }

  /// Crea equipo, membresia de owner y ajustes en una sola transaccion.
  /// Se hace por RPC porque RLS no permitiria los tres pasos por separado.
  Future<Team> createTeam({
    required String name,
    String? shortName,
    String primaryColorHex = '#1B5E20',
    String secondaryColorHex = '#FFD700',
    bool isPublic = true,
  }) async {
    final row = await _db.rpc('create_team', params: {
      'p_name': name,
      'p_short_name': shortName,
      'p_primary_color': primaryColorHex,
      'p_secondary_color': secondaryColorHex,
      'p_is_public': isPublic,
    });
    return Team.fromMap(Map<String, dynamic>.from(row as Map));
  }

  /// Adopta un equipo que todavia no tiene owner (el club del seed).
  Future<void> claimTeam(String teamId) =>
      _db.rpc('claim_team', params: {'p_team_id': teamId});

  Future<Team> update(Team team) async {
    final row = await _db
        .from('teams')
        .update(team.toMap())
        .eq('id', team.id)
        .select()
        .single();
    return Team.fromMap(row);
  }

  /// Mi rol en un equipo. `null` si no soy miembro.
  Future<TeamRole?> myRole(String teamId) async {
    final user = SupabaseService.currentUser;
    if (user == null) return null;

    final row = await _db
        .from('team_members')
        .select('role')
        .eq('team_id', teamId)
        .eq('user_id', user.id)
        .maybeSingle();

    return row == null ? null : TeamRole.parse(row['role']);
  }

  Future<List<TeamMember>> fetchMembers(String teamId) async {
    final rows = await _db
        .from('team_members')
        .select('team_id, user_id, role, profiles(display_name, email, avatar_url)')
        .eq('team_id', teamId);
    return rows.map(TeamMember.fromMap).toList();
  }

  Future<void> changeMemberRole({
    required String teamId,
    required String userId,
    required TeamRole role,
  }) =>
      _db
          .from('team_members')
          .update({'role': role.name})
          .eq('team_id', teamId)
          .eq('user_id', userId);

  Future<void> removeMember({required String teamId, required String userId}) =>
      _db.from('team_members').delete().eq('team_id', teamId).eq('user_id', userId);
}
