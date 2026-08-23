/// Barrel de repositorios.
///
/// Regla del proyecto: los widgets hablan con estos repositorios, nunca
/// con `Supabase.instance.client` directamente. Asi la UI no depende del
/// backend y se puede sustituir por una fuente local en las pruebas.
library;

export 'auth_repository.dart';
export 'match_events_repository.dart';
export 'matches_repository.dart';
export 'players_repository.dart';
export 'rivals_repository.dart';
export 'stats_repository.dart';
export 'teams_repository.dart';
