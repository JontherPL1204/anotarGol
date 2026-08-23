import 'package:flutter/material.dart' show Color;

/// El club. Tabla `public.teams`.
class Team {
  const Team({
    required this.id,
    required this.name,
    this.shortName,
    this.slug,
    this.primaryColorHex = '#1B5E20',
    this.secondaryColorHex = '#FFD700',
    this.logoUrl,
    this.isPublic = true,
  });

  final String id;
  final String name;
  final String? shortName;
  final String? slug;
  final String primaryColorHex;
  final String secondaryColorHex;
  final String? logoUrl;

  /// Si es `true`, cualquiera puede leer plantilla y marcador sin login.
  final bool isPublic;

  Color get primaryColor => _hexToColor(primaryColorHex, 0xFF1B5E20);
  Color get secondaryColor => _hexToColor(secondaryColorHex, 0xFFFFD700);

  factory Team.fromMap(Map<String, dynamic> map) => Team(
        id: map['id'] as String,
        name: map['name'] as String,
        shortName: map['short_name'] as String?,
        slug: map['slug'] as String?,
        primaryColorHex: (map['primary_color'] as String?) ?? '#1B5E20',
        secondaryColorHex: (map['secondary_color'] as String?) ?? '#FFD700',
        logoUrl: map['logo_url'] as String?,
        isPublic: (map['is_public'] as bool?) ?? true,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'short_name': shortName,
        'primary_color': primaryColorHex,
        'secondary_color': secondaryColorHex,
        'logo_url': logoUrl,
        'is_public': isPublic,
      };

  static Color _hexToColor(String hex, int fallback) {
    final clean = hex.replaceFirst('#', '');
    final value = int.tryParse(clean, radix: 16);
    if (value == null || clean.length != 6) return Color(fallback);
    return Color(0xFF000000 | value);
  }
}
