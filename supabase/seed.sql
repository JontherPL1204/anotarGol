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
-- Liga de prueba
-- ---------------------------------------------------------------------
-- El club de ejemplo vive dentro de una liga, como cualquier otro: un
-- equipo suelto contradice el modelo, donde nada se ve sin pertenecer a
-- un grupo.
--
-- Se inserta directo y no con crear_grupo() porque esa funcion exige ser
-- dev, y el seed corre como postgres sin sesion.
insert into public.groups (id, name, slug, description, created_by)
values (
  '9c000000-0000-4000-8000-000000000001',
  'Liga de Prueba',
  'liga-de-prueba',
  'Liga con el club de ejemplo, para probar la app.',
  null
)
on conflict (id) do nothing;

-- Clave de capitan para entrar. Se genera distinta en cada instalacion:
-- una clave fija en un repositorio publico es una clave filtrada.
insert into public.group_invites (group_id, code, created_by, para_capitan, para_admin)
select '9c000000-0000-4000-8000-000000000001',
       public.generar_codigo_invitacion(), null, true, true
where not exists (
  select 1 from public.group_invites
  where group_id = '9c000000-0000-4000-8000-000000000001'
);

-- ---------------------------------------------------------------------
-- Club
-- ---------------------------------------------------------------------
insert into public.teams (id, group_id, name, short_name, slug,
                          primary_color, secondary_color, is_public)
values (
  'a0000000-0000-4000-8000-000000000001',
  '9c000000-0000-4000-8000-000000000001',
  'Pasión Futbolera FC',
  'PFC',
  'pasion-futbolera-fc',
  '#1B5E20',
  '#FFD700',
  false
)
on conflict (id) do update
  set group_id = excluded.group_id,
      is_public = false;

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
-- La cedula es obligatoria de hecho: sin ella el jugador no cuenta para
-- los 11 y el equipo no puede jugar. Estas son validas (digito
-- verificador correcto) y de ejemplo.
insert into public.players (id, team_id, number, full_name, position, position_detail, cedula)
values
  ('b0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001',  1, 'Carlos Navas',      'GK', 'Portero', '1750950006'),
  ('b0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000001',  2, 'Luis Paredes',      'DF', 'Defensa Central', '1750950014'),
  ('b0000000-0000-4000-8000-000000000003', 'a0000000-0000-4000-8000-000000000001',  3, 'Mateo Torres',      'DF', 'Defensa Central', '1750950022'),
  ('b0000000-0000-4000-8000-000000000004', 'a0000000-0000-4000-8000-000000000001',  4, 'Jorge Caicedo',     'DF', 'Lateral Derecho', '1750950030'),
  ('b0000000-0000-4000-8000-000000000005', 'a0000000-0000-4000-8000-000000000001',  6, 'Felipe Valencia',   'DF', 'Lateral Izquierdo', '1750950048'),
  ('b0000000-0000-4000-8000-000000000006', 'a0000000-0000-4000-8000-000000000001',  5, 'Sebastián Méndez',  'MF', 'Mediocampista Defensivo', '1750950055'),
  ('b0000000-0000-4000-8000-000000000007', 'a0000000-0000-4000-8000-000000000001',  8, 'Andrés Gómez',      'MF', 'Mediocampista Central', '1750950063'),
  ('b0000000-0000-4000-8000-000000000008', 'a0000000-0000-4000-8000-000000000001', 10, 'Diego López',       'MF', 'Mediocampista Ofensivo', '1750950071'),
  ('b0000000-0000-4000-8000-000000000009', 'a0000000-0000-4000-8000-000000000001',  7, 'Javier Rodríguez',  'FW', 'Extremo Derecho', '1750950089'),
  ('b0000000-0000-4000-8000-000000000010', 'a0000000-0000-4000-8000-000000000001', 11, 'Gabriel Mina',      'FW', 'Extremo Izquierdo', '1750950097'),
  ('b0000000-0000-4000-8000-000000000011', 'a0000000-0000-4000-8000-000000000001',  9, 'Ronny Benítez',     'FW', 'Delantero Centro', '1750950105')
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
-- Segundo equipo de la liga
-- ---------------------------------------------------------------------
-- Una liga con un solo equipo no sirve para probar nada: no hay a quien
-- retar. Este es el rival del partido que ya estaba programado.
insert into public.teams (id, group_id, name, short_name, slug,
                          primary_color, secondary_color, is_public)
values (
  'b0000000-0000-4000-8000-0000000000f2',
  '9c000000-0000-4000-8000-000000000001',
  'Clásicos FC',
  'CLA',
  'clasicos-fc',
  '#1565C0',
  '#FFFFFF',
  false
)
on conflict (id) do nothing;

insert into public.players (id, team_id, number, full_name, position, position_detail, cedula)
values
  ('c0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-0000000000f2',  1, 'Iván Cabezas', 'GK', 'Portero', '0920450004'),
  ('c0000000-0000-4000-8000-000000000002', 'b0000000-0000-4000-8000-0000000000f2',  2, 'Bryan Quiñónez', 'DF', 'Lateral Derecho', '0920450012'),
  ('c0000000-0000-4000-8000-000000000003', 'b0000000-0000-4000-8000-0000000000f2',  3, 'Marlon Solís', 'DF', 'Defensa Central', '0920450020'),
  ('c0000000-0000-4000-8000-000000000004', 'b0000000-0000-4000-8000-0000000000f2',  4, 'Adrián Vera', 'DF', 'Defensa Central', '0920450038'),
  ('c0000000-0000-4000-8000-000000000005', 'b0000000-0000-4000-8000-0000000000f2',  5, 'Kevin Palacios', 'DF', 'Lateral Izquierdo', '0920450046'),
  ('c0000000-0000-4000-8000-000000000006', 'b0000000-0000-4000-8000-0000000000f2',  6, 'Nixon Chalá', 'MF', 'Mediocampista Defensivo', '0920450053'),
  ('c0000000-0000-4000-8000-000000000007', 'b0000000-0000-4000-8000-0000000000f2',  7, 'Erick Montaño', 'MF', 'Mediocampista Central', '0920450061'),
  ('c0000000-0000-4000-8000-000000000008', 'b0000000-0000-4000-8000-0000000000f2',  8, 'Joao Preciado', 'MF', 'Mediocampista Ofensivo', '0920450079'),
  ('c0000000-0000-4000-8000-000000000009', 'b0000000-0000-4000-8000-0000000000f2',  9, 'Anderson Angulo', 'FW', 'Extremo Derecho', '0920450087'),
  ('c0000000-0000-4000-8000-000000000010', 'b0000000-0000-4000-8000-0000000000f2', 10, 'Michael Corozo', 'FW', 'Delantero Centro', '0920450095'),
  ('c0000000-0000-4000-8000-000000000011', 'b0000000-0000-4000-8000-0000000000f2', 11, 'Steven Arroyo', 'FW', 'Extremo Izquierdo', '0920450103')
on conflict (id) do nothing;

-- El partido del domingo deja de ser contra un nombre suelto: enfrenta a
-- dos equipos de la liga, y por eso los dos lo ven en su cronograma.
update public.matches
set opponent_team_id = 'b0000000-0000-4000-8000-0000000000f2'
where id = 'd0000000-0000-4000-8000-000000000002';

-- ---------------------------------------------------------------------
-- Verificacion rapida
-- ---------------------------------------------------------------------
-- El marcador 2-1 lo calcula el trigger a partir de los eventos: si sale
-- asi, la parte mas delicada del esquema esta funcionando.
select m.opponent_name, m.status, m.team_score, m.opponent_score,
       case when m.status = 'finished' and m.team_score > m.opponent_score
            then 'W' end as result
from public.matches m
where m.team_id = 'a0000000-0000-4000-8000-000000000001'
order by m.kickoff_at;

-- La clave para entrar a la liga de prueba. Anotala: es distinta en
-- cada instalacion.
select
  t.numero_en_grupo as n,
  t.name            as equipo,
  count(p.*) filter (where p.cedula is not null) as con_cedula,
  public.equipo_habilitado(t.id) as habilitado
from public.teams t
left join public.players p on p.team_id = t.id
where t.group_id = '9c000000-0000-4000-8000-000000000001'
group by t.id, t.numero_en_grupo, t.name
order by t.numero_en_grupo;

-- La clave para entrar a la liga de prueba. Anotala: es distinta en
-- cada instalacion.
select g.name as liga, gi.code as clave_de_capitan
from public.groups g
join public.group_invites gi on gi.group_id = g.id
where g.id = '9c000000-0000-4000-8000-000000000001';
