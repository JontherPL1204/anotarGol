import 'enums.dart';

/// Fila de la vista `public.player_stats`.
///
/// El calculo vive en Postgres, no en Dart: la app pide una fila por
/// jugador en vez de descargarse todos los eventos para contarlos.
class PlayerStats {
  const PlayerStats({
    required this.playerId,
    required this.teamId,
    required this.fullName,
    this.number,
    this.position = PlayerPosition.mf,
    this.positionDetail,
    this.photoUrl,
    this.isActive = true,
    this.appearances = 0,
    this.starts = 0,
    this.minutesPlayed = 0,
    this.goals = 0,
    this.ownGoals = 0,
    this.assists = 0,
    this.yellowCards = 0,
    this.redCards = 0,
  });

  final String playerId;
  final String teamId;
  final String fullName;
  final int? number;
  final PlayerPosition position;
  final String? positionDetail;
  final String? photoUrl;
  final bool isActive;

  final int appearances;
  final int starts;
  final int minutesPlayed;
  final int goals;
  final int ownGoals;
  final int assists;
  final int yellowCards;
  final int redCards;

  double get goalsPerMatch => appearances == 0 ? 0 : goals / appearances;

  /// Participaciones directas en gol (gol + asistencia).
  int get goalContributions => goals + assists;

  factory PlayerStats.fromMap(Map<String, dynamic> map) => PlayerStats(
        playerId: map['player_id'] as String,
        teamId: map['team_id'] as String,
        fullName: map['full_name'] as String,
        number: (map['number'] as num?)?.toInt(),
        position: PlayerPosition.parse(map['position']),
        positionDetail: map['position_detail'] as String?,
        photoUrl: map['photo_url'] as String?,
        isActive: (map['is_active'] as bool?) ?? true,
        appearances: (map['appearances'] as num?)?.toInt() ?? 0,
        starts: (map['starts'] as num?)?.toInt() ?? 0,
        minutesPlayed: (map['minutes_played'] as num?)?.toInt() ?? 0,
        goals: (map['goals'] as num?)?.toInt() ?? 0,
        ownGoals: (map['own_goals'] as num?)?.toInt() ?? 0,
        assists: (map['assists'] as num?)?.toInt() ?? 0,
        yellowCards: (map['yellow_cards'] as num?)?.toInt() ?? 0,
        redCards: (map['red_cards'] as num?)?.toInt() ?? 0,
      );
}
