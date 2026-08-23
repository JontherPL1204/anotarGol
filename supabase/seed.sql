-- =====================================================================
-- Anotar Gol - seed
-- =====================================================================
-- Migra a la base los datos que hoy estan quemados en el codigo:
--   * los 11 titulares de lib/plantilla.dart
--   * el "Proximo encuentro: Domingo 16:00 vs. Clasicos FC" de homescreen
--
-- El equipo se crea SIN owner y con is_public = true, para que la app
-- funcione en modo lectura antes de que exista cualquier usuario.
-- Despues de registrarte, ejecuta desde la app o el SQL editor:
--
--   select public.claim_team('a0000000-0000-4000-8000-000000000001');
--
-- ...y quedaras como owner del club.
--
-- Es idempotente: se puede correr varias veces sin duplicar nada.
-- =====================================================================

-- Zona horaria usada para el horario de los partidos. Cambiala si el
-- club no esta en Ecuador (ej. 'America/Bogota', 'America/Mexico_City').
-- Se escribe literal a proposito: los meta-comandos de psql (\set) no
-- funcionan al pegar este archivo en el SQL Editor de Supabase.

-- ---------------------------------------------------------------------
-- Club
-- ---------------------------------------------------------------------
insert into public.teams (id, name, short_name, slug, primary_color, secondary_color, is_public)
values (
  'a0000000-0000-4000-8000-000000000001',
  'Pasión Futbolera FC',
  'PFC',
  'pasion-futbolera-fc',
  '#1B5E20',
  '#FFD700',
  true
)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- Temporada
-- ---------------------------------------------------------------------
insert into public.seasons (id, team_id, name, starts_on, ends_on, is_current)
values (
  'c0000000-0000-4000-8000-000000000001',
  'a0000000-0000-4000-8000-000000000001',
  'Temporada 2026',
  date '2026-01-15',
  date '2026-11-30',
  true
)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- Plantilla (los 11 de lib/plantilla.dart)
-- ---------------------------------------------------------------------
insert into public.players (id, team_id, number, full_name, position, position_detail)
values
  ('b0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001',  1, 'Carlos Navas',      'GK', 'Portero'),
  ('b0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000001',  2, 'Luis Paredes',      'DF', 'Defensa Central'),
  ('b0000000-0000-4000-8000-000000000003', 'a0000000-0000-4000-8000-000000000001',  3, 'Mateo Torres',      'DF', 'Defensa Central'),
  ('b0000000-0000-4000-8000-000000000004', 'a0000000-0000-4000-8000-000000000001',  4, 'Jorge Caicedo',     'DF', 'Lateral Derecho'),
  ('b0000000-0000-4000-8000-000000000005', 'a0000000-0000-4000-8000-000000000001',  6, 'Felipe Valencia',   'DF', 'Lateral Izquierdo'),
  ('b0000000-0000-4000-8000-000000000006', 'a0000000-0000-4000-8000-000000000001',  5, 'Sebastián Méndez',  'MF', 'Mediocampista Defensivo'),
  ('b0000000-0000-4000-8000-000000000007', 'a0000000-0000-4000-8000-000000000001',  8, 'Andrés Gómez',      'MF', 'Mediocampista Central'),
  ('b0000000-0000-4000-8000-000000000008', 'a0000000-0000-4000-8000-000000000001', 10, 'Diego López',       'MF', 'Mediocampista Ofensivo'),
  ('b0000000-0000-4000-8000-000000000009', 'a0000000-0000-4000-8000-000000000001',  7, 'Javier Rodríguez',  'FW', 'Extremo Derecho'),
  ('b0000000-0000-4000-8000-000000000010', 'a0000000-0000-4000-8000-000000000001', 11, 'Gabriel Mina',      'FW', 'Extremo Izquierdo'),
  ('b0000000-0000-4000-8000-000000000011', 'a0000000-0000-4000-8000-000000000001',  9, 'Ronny Benítez',     'FW', 'Delantero Centro')
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- Partidos
-- ---------------------------------------------------------------------
-- 1) Partido jugado la semana pasada (de visita, ganado 2-1).
--    OJO: team_score / opponent_score no se escriben aca; los calcula
--    el trigger a partir de los eventos de mas abajo.
insert into public.matches (
  id, team_id, season_id, opponent_name, kickoff_at, venue, competition,
  is_home, status
)
values (
  'd0000000-0000-4000-8000-000000000001',
  'a0000000-0000-4000-8000-000000000001',
  'c0000000-0000-4000-8000-000000000001',
  'Deportivo Andino',
  ((current_date - 7) + time '15:30') at time zone 'America/Guayaquil',
  'Estadio Municipal',
  'Liga Barrial',
  false,
  'finished'
)
on conflict (id) do nothing;

-- 2) Proximo partido: domingo 16:00 vs Clasicos FC (el que hoy esta
--    quemado como texto fijo en homescreen.dart).
insert into public.matches (
  id, team_id, season_id, opponent_name, kickoff_at, venue, competition,
  is_home, status
)
values (
  'd0000000-0000-4000-8000-000000000002',
  'a0000000-0000-4000-8000-000000000001',
  'c0000000-0000-4000-8000-000000000001',
  'Clásicos FC',
  ((current_date + (case when extract(dow from current_date)::int = 0
                         then 7
                         else 7 - extract(dow from current_date)::int end))
    + time '16:00') at time zone 'America/Guayaquil',
  'Cancha del Club',
  'Liga Barrial',
  true,
  'scheduled'
)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- Once inicial del partido jugado
-- ---------------------------------------------------------------------
insert into public.match_lineups (match_id, player_id, team_id, is_starter, shirt_number, position, minutes_played)
select
  'd0000000-0000-4000-8000-000000000001',
  p.id,
  p.team_id,
  true,
  p.number,
  p.position,
  90
from public.players p
where p.team_id = 'a0000000-0000-4000-8000-000000000001'
on conflict (match_id, player_id) do nothing;

-- ---------------------------------------------------------------------
-- Eventos del partido jugado -> el marcador sale de aca
-- ---------------------------------------------------------------------
insert into public.match_events (
  id, match_id, team_id, player_id, assist_player_id, type, side, minute, description
)
values
  -- 23' gol de Ronny Benítez, asistencia de Diego López
  ('e0000000-0000-4000-8000-000000000001',
   'd0000000-0000-4000-8000-000000000001',
   'a0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000011',
   'b0000000-0000-4000-8000-000000000008',
   'goal', 'us', 23, 'Contragolpe por derecha'),

  -- 55' amarilla a Sebastián Méndez
  ('e0000000-0000-4000-8000-000000000002',
   'd0000000-0000-4000-8000-000000000001',
   'a0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000006',
   null,
   'yellow_card', 'us', 55, 'Falta táctica'),

  -- 67' gol de Gabriel Mina
  ('e0000000-0000-4000-8000-000000000003',
   'd0000000-0000-4000-8000-000000000001',
   'a0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000010',
   null,
   'goal', 'us', 67, 'Remate desde fuera del área'),

  -- 80' descuento del rival
  ('e0000000-0000-4000-8000-000000000004',
   'd0000000-0000-4000-8000-000000000001',
   'a0000000-0000-4000-8000-000000000001',
   null,
   null,
   'goal', 'them', 80, 'Penal')
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- Verificacion rapida
-- ---------------------------------------------------------------------
-- Debe devolver: Deportivo Andino | finished | 2 | 1 | W
select opponent_name, status, team_score, opponent_score, result
from public.match_summary
where team_id = 'a0000000-0000-4000-8000-000000000001'
order by kickoff_at;
