import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_service.dart';
import '../models/models.dart';

/// Retos entre capitanes.
///
/// Retar y responder son cosa de capitán a capitán: las funciones de la
/// base lo comprueban con `can_captain`, así que aquí no se replica esa
/// regla. La pantalla oculta los botones por comodidad, no por seguridad.
class ChallengesRepository {
  const ChallengesRepository();

  SupabaseClient get _db => SupabaseService.client;

  /// Los equipos de la liga, para elegir a quién retar.
  Future<List<EquipoDelGrupo>> equiposParaRetar(String groupId) async {
    final filas = await _db.rpc('equipos_del_grupo', params: {
      'p_group_id': groupId,
    });
    return (filas as List)
        .map((f) => EquipoDelGrupo.fromMap(Map<String, dynamic>.from(f as Map)))
        .where((e) => e.sePuedeRetar)
        .toList();
  }

  /// Los retos del equipo, enviados y recibidos, en una sola lista.
  Future<List<Reto>> misRetos(String teamId) async {
    final filas = await _db.rpc('mis_retos', params: {'p_team_id': teamId});
    return (filas as List)
        .map((f) => Reto.fromMap(Map<String, dynamic>.from(f as Map)))
        .toList();
  }

  /// Manda el reto. La base rechaza el horario que choque con la agenda
  /// de cualquiera de los dos equipos dentro de la misma liga.
  Future<void> retar({
    required String miEquipoId,
    required String rivalId,
    required DateTime cuando,
    String? lugar,
    int minutos = 90,
    int cambios = 5,
    String? mensaje,
  }) =>
      _db.rpc('retar_equipo', params: {
        'p_from_team_id': miEquipoId,
        'p_to_team_id': rivalId,
        'p_kickoff': cuando.toUtc().toIso8601String(),
        'p_venue': lugar,
        'p_duracion': minutos,
        'p_cambios': cambios,
        'p_mensaje': mensaje,
      });

  /// Aceptar o rechazar. Aceptar es "quedaron de acuerdo": la base crea
  /// el partido y lo pone en el cronograma.
  Future<void> responder({required String retoId, required bool aceptar}) =>
      _db.rpc('responder_reto', params: {
        'p_challenge_id': retoId,
        'p_aceptar': aceptar,
      });
}
