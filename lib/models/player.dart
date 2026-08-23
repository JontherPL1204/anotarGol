import 'enums.dart';

/// Un jugador de la plantilla. Tabla `public.players`.
///
/// Reemplaza la lista `List<Map<String, String>>` quemada dentro de
/// `lib/plantilla.dart`.
class Player {
  const Player({
    required this.id,
    required this.teamId,
    required this.fullName,
    this.number,
    this.position = PlayerPosition.mf,
    this.positionDetail,
    this.photoUrl,
    this.birthDate,
    this.isActive = true,
  });

  final String id;
  final String teamId;
  final String fullName;
  final int? number;
  final PlayerPosition position;

  /// Texto libre como 'Lateral Derecho'. Si falta, se usa la etiqueta
  /// generica de la posicion.
  final String? positionDetail;
  final String? photoUrl;
  final DateTime? birthDate;
  final bool isActive;

  String get positionLabel => positionDetail?.trim().isNotEmpty == true
      ? positionDetail!.trim()
      : position.label;

  String get shirtLabel => number?.toString() ?? '-';

  factory Player.fromMap(Map<String, dynamic> map) => Player(
        id: map['id'] as String,
        teamId: map['team_id'] as String,
        fullName: map['full_name'] as String,
        number: (map['number'] as num?)?.toInt(),
        position: PlayerPosition.parse(map['position']),
        positionDetail: map['position_detail'] as String?,
        photoUrl: map['photo_url'] as String?,
        birthDate: map['birth_date'] == null
            ? null
            : DateTime.parse(map['birth_date'] as String),
        isActive: (map['is_active'] as bool?) ?? true,
      );

  Map<String, dynamic> toMap() => {
        'team_id': teamId,
        'full_name': fullName,
        'number': number,
        'position': position.wire,
        'position_detail': positionDetail,
        'photo_url': photoUrl,
        'birth_date': birthDate?.toIso8601String().split('T').first,
        'is_active': isActive,
      };

  Player copyWith({
    String? fullName,
    int? number,
    PlayerPosition? position,
    String? positionDetail,
    String? photoUrl,
    bool? isActive,
  }) =>
      Player(
        id: id,
        teamId: teamId,
        fullName: fullName ?? this.fullName,
        number: number ?? this.number,
        position: position ?? this.position,
        positionDetail: positionDetail ?? this.positionDetail,
        photoUrl: photoUrl ?? this.photoUrl,
        birthDate: birthDate,
        isActive: isActive ?? this.isActive,
      );
}
