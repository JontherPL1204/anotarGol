import 'enums.dart';

/// Un partido. Tabla `public.matches` y vista `public.match_summary`.
///
/// Se llama `FootballMatch` y no `Match` porque `Match` ya existe en
/// `dart:core` (el resultado de una expresion regular).
///
/// El marcador se guarda desde la perspectiva del club
/// (`teamScore` / `opponentScore`) mas la bandera `isHome`. La vista
/// `match_summary` ya entrega ademas local/visitante resueltos.
class FootballMatch {
  const FootballMatch({
    required this.id,
    required this.teamId,
    required this.opponentName,
    required this.kickoffAt,
    this.seasonId,
    this.opponentLogoUrl,
    this.venue,
    this.competition,
    this.isHome = true,
    this.status = MatchStatus.scheduled,
    this.teamScore = 0,
    this.opponentScore = 0,
    this.notes,
    this.teamName,
    this.result,
  });

  final String id;
  final String teamId;
  final String? seasonId;
  final String opponentName;
  final String? opponentLogoUrl;
  final DateTime kickoffAt;
  final String? venue;
  final String? competition;
  final bool isHome;
  final MatchStatus status;

  /// Derivados por trigger desde `match_events`. No se escriben a mano.
  final int teamScore;
  final int opponentScore;

  final String? notes;

  /// Solo viene de la vista `match_summary`.
  final String? teamName;

  /// 'W' | 'D' | 'L'. Null si el partido no ha terminado.
  final String? result;

  String get homeName => isHome ? (teamName ?? 'Nosotros') : opponentName;
  String get awayName => isHome ? opponentName : (teamName ?? 'Nosotros');
  int get homeScore => isHome ? teamScore : opponentScore;
  int get awayScore => isHome ? opponentScore : teamScore;

  String get scoreLabel => '$homeScore - $awayScore';
  bool get isLive => status == MatchStatus.live;
  bool get isFinished => status == MatchStatus.finished;

  factory FootballMatch.fromMap(Map<String, dynamic> map) => FootballMatch(
        id: map['id'] as String,
        teamId: map['team_id'] as String,
        seasonId: map['season_id'] as String?,
        opponentName: map['opponent_name'] as String,
        opponentLogoUrl: map['opponent_logo_url'] as String?,
        kickoffAt: DateTime.parse(map['kickoff_at'] as String).toLocal(),
        venue: map['venue'] as String?,
        competition: map['competition'] as String?,
        isHome: (map['is_home'] as bool?) ?? true,
        status: MatchStatus.parse(map['status']),
        teamScore: (map['team_score'] as num?)?.toInt() ?? 0,
        opponentScore: (map['opponent_score'] as num?)?.toInt() ?? 0,
        notes: map['notes'] as String?,
        teamName: map['team_name'] as String?,
        result: map['result'] as String?,
      );

  /// Solo campos escribibles: el marcador queda fuera a proposito.
  Map<String, dynamic> toMap() => {
        'team_id': teamId,
        'season_id': seasonId,
        'opponent_name': opponentName,
        'opponent_logo_url': opponentLogoUrl,
        'kickoff_at': kickoffAt.toUtc().toIso8601String(),
        'venue': venue,
        'competition': competition,
        'is_home': isHome,
        'status': status.name,
        'notes': notes,
      };
}
