import 'enums.dart';

/// Un evento dentro del partido. Tabla `public.match_events`.
///
/// Es el cambio conceptual mas importante del proyecto: el gol deja de
/// ser un `int _goles` en memoria y pasa a ser un hecho con minuto,
/// autor y asistencia, del que se derivan marcador e historial.
class MatchEvent {
  const MatchEvent({
    required this.id,
    required this.matchId,
    required this.teamId,
    required this.type,
    this.side = TeamSide.us,
    this.playerId,
    this.assistPlayerId,
    this.minute,
    this.isOwnGoal = false,
    this.description,
    this.createdAt,
  });

  final String id;
  final String matchId;
  final String teamId;
  final MatchEventType type;
  final TeamSide side;

  /// Null cuando el evento es del rival, o cuando se anota un gol
  /// rapido sin decir quien lo hizo.
  final String? playerId;
  final String? assistPlayerId;
  final int? minute;
  final bool isOwnGoal;
  final String? description;
  final DateTime? createdAt;

  bool get isGoal => type == MatchEventType.goal;

  /// A quien le suma este gol. Un autogol suma para el otro lado.
  TeamSide? get scoringSide {
    if (!isGoal) return null;
    if (!isOwnGoal) return side;
    return side == TeamSide.us ? TeamSide.them : TeamSide.us;
  }

  String get minuteLabel => minute == null ? '' : "$minute'";

  factory MatchEvent.fromMap(Map<String, dynamic> map) => MatchEvent(
        id: map['id'] as String,
        matchId: map['match_id'] as String,
        teamId: map['team_id'] as String,
        type: MatchEventType.parse(map['type']),
        side: TeamSide.parse(map['side']),
        playerId: map['player_id'] as String?,
        assistPlayerId: map['assist_player_id'] as String?,
        minute: (map['minute'] as num?)?.toInt(),
        isOwnGoal: (map['is_own_goal'] as bool?) ?? false,
        description: map['description'] as String?,
        createdAt: map['created_at'] == null
            ? null
            : DateTime.parse(map['created_at'] as String).toLocal(),
      );

  Map<String, dynamic> toMap() => {
        'match_id': matchId,
        'team_id': teamId,
        'type': type.wire,
        'side': side.name,
        'player_id': playerId,
        'assist_player_id': assistPlayerId,
        'minute': minute,
        'is_own_goal': isOwnGoal,
        'description': description,
      };
}
