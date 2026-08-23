-- =====================================================================
-- Anotar Gol - 35 | No se podía borrar a un jugador con eventos
-- =====================================================================
-- Encontrado al limpiar los jugadores sin cédula del club de ejemplo:
--
--   ERROR: null value in column "team_id" of relation "match_events"
--          violates not-null constraint
--   ...
--   UPDATE ONLY match_events SET player_id = NULL, team_id = NULL
--
-- Causa:
--   Las llaves foráneas compuestas `(player_id, team_id)` se declararon
--   con `on delete set null`. Esa acción anula TODAS las columnas de la
--   llave, no solo la que apunta al jugador. Y `team_id` es obligatoria,
--   además de formar parte de la otra llave, la del partido.
--
--   Resultado: borrar a un jugador que tenga cualquier evento fallaba
--   siempre. Un capitán no podía sacar del club a alguien que hubiera
--   metido un gol.
--
-- El mismo error estaba en cuatro llaves:
--   match_events -> players (goleador y asistente)
--   match_events -> rival_players
--   matches      -> rivals
--
-- Arreglo:
--   PostgreSQL 15 en adelante permite decir QUÉ columnas se anulan:
--   `on delete set null (columna)`. Se anula solo la que apunta al
--   jugador; `team_id` se queda, que es lo correcto: el evento sigue
--   siendo de ese equipo aunque ya no se sepa quién lo hizo.
--
-- Nota: la baja normal de un jugador es lógica (`is_active = false`),
-- justamente para no perder el autor de los goles. Este arreglo es para
-- el borrado de verdad, que también tiene que funcionar.
-- =====================================================================

-- ---------------------------------------------------------------------
-- match_events -> players (el goleador)
-- ---------------------------------------------------------------------
alter table public.match_events
  drop constraint if exists match_events_player_id_team_id_fkey;

alter table public.match_events
  add constraint match_events_player_id_team_id_fkey
  foreign key (player_id, team_id)
  references public.players (id, team_id)
  on delete set null (player_id);

-- ---------------------------------------------------------------------
-- match_events -> players (la asistencia)
-- ---------------------------------------------------------------------
alter table public.match_events
  drop constraint if exists match_events_assist_player_id_team_id_fkey;

alter table public.match_events
  add constraint match_events_assist_player_id_team_id_fkey
  foreign key (assist_player_id, team_id)
  references public.players (id, team_id)
  on delete set null (assist_player_id);

-- ---------------------------------------------------------------------
-- match_events -> rival_players
-- ---------------------------------------------------------------------
alter table public.match_events
  drop constraint if exists match_events_rival_player_fk;

alter table public.match_events
  add constraint match_events_rival_player_fk
  foreign key (rival_player_id, team_id)
  references public.rival_players (id, team_id)
  on delete set null (rival_player_id);

-- ---------------------------------------------------------------------
-- matches -> rivals
-- ---------------------------------------------------------------------
alter table public.matches
  drop constraint if exists matches_rival_fk;

alter table public.matches
  add constraint matches_rival_fk
  foreign key (rival_id, team_id)
  references public.rivals (id, team_id)
  on delete set null (rival_id);
