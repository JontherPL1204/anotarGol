import 'enums.dart';

/// Un jugador del equipo contrario. Tabla `public.rival_players`.
///
/// [isImaginary] es la parte importante: cuando no se conocen los datos
/// del rival, la app genera una plantilla y la marca. Esa marca tiene que
/// verse siempre en la interfaz; si no, serian datos inventados
/// presentados como ciertos.
class RivalPlayer {
  const RivalPlayer({
    required this.id,
    required this.rivalId,
    required this.teamId,
    required this.fullName,
    this.number,
    this.position = PlayerPosition.mf,
    this.positionDetail,
    this.isImaginary = false,
    this.isActive = true,
  });

  final String id;
  final String rivalId;
  final String teamId;
  final String fullName;
  final int? number;
  final PlayerPosition position;
  final String? positionDetail;
  final bool isImaginary;
  final bool isActive;

  String get positionLabel => positionDetail?.trim().isNotEmpty == true
      ? positionDetail!.trim()
      : position.label;

  String get shirtLabel => number?.toString() ?? '-';

  factory RivalPlayer.fromMap(Map<String, dynamic> map) => RivalPlayer(
        id: map['id'] as String,
        rivalId: map['rival_id'] as String,
        teamId: map['team_id'] as String,
        fullName: map['full_name'] as String,
        number: (map['number'] as num?)?.toInt(),
        position: PlayerPosition.parse(map['position']),
        positionDetail: map['position_detail'] as String?,
        isImaginary: (map['is_imaginary'] as bool?) ?? false,
        isActive: (map['is_active'] as bool?) ?? true,
      );

  Map<String, dynamic> toMap() => {
        'rival_id': rivalId,
        'team_id': teamId,
        'full_name': fullName,
        'number': number,
        'position': position.wire,
        'position_detail': positionDetail,
        'is_imaginary': isImaginary,
        'is_active': isActive,
      };

  RivalPlayer copyWith({
    String? fullName,
    int? number,
    PlayerPosition? position,
    String? positionDetail,
    bool? isImaginary,
  }) =>
      RivalPlayer(
        id: id,
        rivalId: rivalId,
        teamId: teamId,
        fullName: fullName ?? this.fullName,
        number: number ?? this.number,
        position: position ?? this.position,
        positionDetail: positionDetail ?? this.positionDetail,
        isImaginary: isImaginary ?? this.isImaginary,
        isActive: isActive,
      );
}
