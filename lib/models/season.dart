/// Temporada del club. Tabla `public.seasons`.
class Season {
  const Season({
    required this.id,
    required this.teamId,
    required this.name,
    this.startsOn,
    this.endsOn,
    this.isCurrent = false,
  });

  final String id;
  final String teamId;
  final String name;
  final DateTime? startsOn;
  final DateTime? endsOn;
  final bool isCurrent;

  factory Season.fromMap(Map<String, dynamic> map) => Season(
        id: map['id'] as String,
        teamId: map['team_id'] as String,
        name: map['name'] as String,
        startsOn: map['starts_on'] == null
            ? null
            : DateTime.parse(map['starts_on'] as String),
        endsOn: map['ends_on'] == null
            ? null
            : DateTime.parse(map['ends_on'] as String),
        isCurrent: (map['is_current'] as bool?) ?? false,
      );

  Map<String, dynamic> toMap() => {
        'team_id': teamId,
        'name': name,
        'starts_on': startsOn?.toIso8601String().split('T').first,
        'ends_on': endsOn?.toIso8601String().split('T').first,
        'is_current': isCurrent,
      };
}
