/// Espejo en Dart de los ENUM de Postgres (migracion 00).
///
/// Si agregas un valor en la base, agregalo tambien aca. El parseo nunca
/// lanza excepcion: ante un valor desconocido cae al valor por defecto,
/// para que una app vieja no se caiga contra una base mas nueva.

library;

enum TeamRole {
  owner,
  admin,
  coach,
  player,
  viewer;

  static TeamRole parse(Object? value) => _parse(TeamRole.values, value, viewer);

  /// Puede editar jugadores, partidos y eventos.
  bool get canEdit => this == owner || this == admin || this == coach;

  /// Puede gestionar miembros y ajustes del club.
  bool get canAdmin => this == owner || this == admin;
}

enum MatchStatus {
  scheduled,
  live,
  finished,
  postponed,
  cancelled;

  static MatchStatus parse(Object? value) =>
      _parse(MatchStatus.values, value, scheduled);

  String get label => switch (this) {
        MatchStatus.scheduled => 'Programado',
        MatchStatus.live => 'En vivo',
        MatchStatus.finished => 'Finalizado',
        MatchStatus.postponed => 'Aplazado',
        MatchStatus.cancelled => 'Cancelado',
      };
}

enum MatchEventType {
  goal,
  yellowCard,
  redCard,
  penaltyMissed,
  substitutionIn,
  substitutionOut,
  note;

  /// El nombre tal cual lo espera Postgres (snake_case).
  String get wire => switch (this) {
        MatchEventType.goal => 'goal',
        MatchEventType.yellowCard => 'yellow_card',
        MatchEventType.redCard => 'red_card',
        MatchEventType.penaltyMissed => 'penalty_missed',
        MatchEventType.substitutionIn => 'substitution_in',
        MatchEventType.substitutionOut => 'substitution_out',
        MatchEventType.note => 'note',
      };

  static MatchEventType parse(Object? value) {
    final raw = value?.toString();
    return MatchEventType.values.firstWhere(
      (e) => e.wire == raw,
      orElse: () => note,
    );
  }

  String get label => switch (this) {
        MatchEventType.goal => 'Gol',
        MatchEventType.yellowCard => 'Tarjeta amarilla',
        MatchEventType.redCard => 'Tarjeta roja',
        MatchEventType.penaltyMissed => 'Penal errado',
        MatchEventType.substitutionIn => 'Entra',
        MatchEventType.substitutionOut => 'Sale',
        MatchEventType.note => 'Nota',
      };
}

enum TeamSide {
  us,
  them;

  static TeamSide parse(Object? value) => _parse(TeamSide.values, value, us);
}

enum PlayerPosition {
  gk,
  df,
  mf,
  fw;

  String get wire => name.toUpperCase();

  static PlayerPosition parse(Object? value) {
    final raw = value?.toString().toLowerCase();
    return PlayerPosition.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => mf,
    );
  }

  String get label => switch (this) {
        PlayerPosition.gk => 'Portero',
        PlayerPosition.df => 'Defensa',
        PlayerPosition.mf => 'Mediocampista',
        PlayerPosition.fw => 'Delantero',
      };
}

T _parse<T extends Enum>(List<T> values, Object? value, T fallback) {
  final raw = value?.toString();
  for (final v in values) {
    if (v.name == raw) return v;
  }
  return fallback;
}
