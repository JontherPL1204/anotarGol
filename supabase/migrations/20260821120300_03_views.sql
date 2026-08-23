-- =====================================================================
-- Anotar Gol - 03 | Vistas de lectura
-- =====================================================================
-- security_invoker = true es OBLIGATORIO aqui. Sin eso, la vista se
-- ejecutaria con los permisos de quien la creo (postgres) y filtraria
-- datos de equipos privados saltandose RLS.
-- =====================================================================

-- ---------------------------------------------------------------------
-- player_stats: la tabla de estadisticas que pedia la fase 4 del plan
-- ---------------------------------------------------------------------
drop view if exists public.player_stats;
create view public.player_stats
with (security_invoker = true)
as
select
  p.id        as player_id,
  p.team_id,
  p.full_name,
  p.number,
  p.position,
  p.position_detail,
  p.photo_url,
  p.is_active,

  (select count(*) from public.match_lineups l
    where l.player_id = p.id)                            as appearances,
  (select count(*) from public.match_lineups l
    where l.player_id = p.id and l.is_starter)           as starts,
  (select coalesce(sum(l.minutes_played), 0) from public.match_lineups l
    where l.player_id = p.id)                            as minutes_played,

  (select count(*) from public.match_events e
    where e.player_id = p.id
      and e.type = 'goal'
      and e.side = 'us'
      and not e.is_own_goal)                             as goals,
  (select count(*) from public.match_events e
    where e.player_id = p.id
      and e.type = 'goal'
      and e.is_own_goal)                                 as own_goals,
  (select count(*) from public.match_events e
    where e.assist_player_id = p.id)                     as assists,
  (select count(*) from public.match_events e
    where e.player_id = p.id and e.type = 'yellow_card')  as yellow_cards,
  (select count(*) from public.match_events e
    where e.player_id = p.id and e.type = 'red_card')     as red_cards
from public.players p;

comment on view public.player_stats is
  'Goles, asistencias, tarjetas y presencias por jugador. Respeta RLS.';

-- ---------------------------------------------------------------------
-- match_summary: traduce el marcador interno a lenguaje de cancha
-- ---------------------------------------------------------------------
-- La tabla matches guarda team_score/opponent_score (perspectiva del
-- club). Esta vista devuelve ademas local/visitante, ya resuelto, para
-- que la UI no tenga que hacer ese if.
drop view if exists public.match_summary;
create view public.match_summary
with (security_invoker = true)
as
select
  m.id,
  m.team_id,
  m.season_id,
  t.name           as team_name,
  t.short_name     as team_short_name,
  t.logo_url       as team_logo_url,
  m.opponent_name,
  m.opponent_logo_url,
  m.kickoff_at,
  m.venue,
  m.competition,
  m.status,
  m.is_home,
  m.team_score,
  m.opponent_score,
  m.notes,

  case when m.is_home then t.name else m.opponent_name end        as home_name,
  case when m.is_home then m.opponent_name else t.name end        as away_name,
  case when m.is_home then m.team_score else m.opponent_score end as home_score,
  case when m.is_home then m.opponent_score else m.team_score end as away_score,

  case
    when m.status <> 'finished' then null
    when m.team_score > m.opponent_score then 'W'
    when m.team_score = m.opponent_score then 'D'
    else 'L'
  end as result,

  (select count(*) from public.match_events e
    where e.match_id = m.id and e.type = 'goal') as total_goal_events,

  m.created_at,
  m.updated_at
from public.matches m
join public.teams t on t.id = m.team_id;

comment on view public.match_summary is
  'Partidos con local/visitante y resultado (W/D/L) ya calculados.';

grant select on public.player_stats   to anon, authenticated;
grant select on public.match_summary  to anon, authenticated;
