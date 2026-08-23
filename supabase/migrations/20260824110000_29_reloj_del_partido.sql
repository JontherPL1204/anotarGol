-- =====================================================================
-- Anotar Gol - 29 | El reloj del partido
-- =====================================================================
-- Hasta aquí "en vivo" significaba solo que los cambios llegaban al
-- instante a los demás dispositivos. La app NO sabía en qué minuto iba
-- el partido: el minuto de cada gol se escribía a mano, y nadie ponía el
-- partido en `live` salvo a mano.
--
-- La hora y la duración que negocian los capitanes ya se guardaban, pero
-- solo servían para planificar: detectar choques de horario y calcular
-- cuándo termina en el cronograma. Ahora además gobiernan el partido.
--
-- Decisión: el partido NO arranca solo al llegar la hora.
--   Los equipos llegan tarde, la cancha está ocupada, llueve. Un partido
--   que se pusiera en marcha solo estaría contando minutos que nadie
--   jugó, y el marcador quedaría con goles en minutos falsos.
--   En su lugar: al llegar la hora acordada el partido queda "listo para
--   empezar", y el capitán pulsa iniciar. El reloj cuenta desde ese
--   momento real.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Los tiempos reales del partido
-- ---------------------------------------------------------------------
alter table public.matches
  add column if not exists started_at            timestamptz,
  add column if not exists descanso_at           timestamptz,
  add column if not exists segundo_tiempo_at     timestamptz,
  add column if not exists ended_at              timestamptz,
  add column if not exists minutos_agregados     smallint not null default 0;

comment on column public.matches.started_at is
  'Cuando el capitán arrancó de verdad, no la hora acordada. El reloj cuenta desde aquí.';
comment on column public.matches.descanso_at is
  'Fin del primer tiempo. Mientras esté puesto y no haya segundo tiempo, el reloj está en pausa.';

-- ---------------------------------------------------------------------
-- 2. El minuto actual
-- ---------------------------------------------------------------------
-- Convención futbolera: el primer segundo ya es el minuto 1.
create or replace function public.minuto_actual(p_match_id uuid)
returns int
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  m         public.matches;
  v_mitad   int;
  v_corridos int;
begin
  select * into m from public.matches where id = p_match_id;
  if m.id is null or m.started_at is null then
    return 0;
  end if;

  v_mitad := greatest(1, m.duration_minutes / 2);

  -- Terminado: se queda en lo que duró.
  if m.ended_at is not null then
    return v_mitad * 2 + m.minutos_agregados;
  end if;

  -- Descanso: el reloj se congela al final del primer tiempo.
  if m.descanso_at is not null and m.segundo_tiempo_at is null then
    return v_mitad;
  end if;

  -- Segundo tiempo en curso.
  if m.segundo_tiempo_at is not null then
    v_corridos := floor(extract(epoch from (now() - m.segundo_tiempo_at)) / 60)::int + 1;
    return least(v_mitad + v_corridos, v_mitad * 2 + m.minutos_agregados + 5);
  end if;

  -- Primer tiempo en curso.
  v_corridos := floor(extract(epoch from (now() - m.started_at)) / 60)::int + 1;
  return least(v_corridos, v_mitad + 5);
end;
$$;

grant execute on function public.minuto_actual(uuid) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 3. Manejar el partido
-- ---------------------------------------------------------------------
create or replace function public.iniciar_partido(p_match_id uuid)
returns public.matches
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  m public.matches;
begin
  select * into m from public.matches where id = p_match_id;
  if m.id is null then
    raise exception 'Ese partido no existe' using errcode = 'P0002';
  end if;

  if not (public.can_captain(m.team_id) or public.can_edit_team(m.team_id)) then
    raise exception 'Solo el capitán o el cuerpo técnico pueden iniciar el partido'
      using errcode = '42501';
  end if;

  if m.status <> 'scheduled' then
    raise exception 'Ese partido ya no está programado' using errcode = '23514';
  end if;

  -- No se arranca un partido con horas de anticipación: la hora acordada
  -- es un compromiso entre los dos capitanes, no una sugerencia.
  if now() < m.kickoff_at - interval '30 minutes' then
    raise exception 'Todavía falta para la hora acordada (%)',
      to_char(m.kickoff_at, 'DD/MM HH24:MI')
      using errcode = '23514',
            hint = 'Se puede iniciar desde 30 minutos antes.';
  end if;

  update public.matches
  set status = 'live', started_at = now()
  where id = p_match_id
  returning * into m;

  return m;
end;
$$;

create or replace function public.ir_al_descanso(p_match_id uuid)
returns public.matches
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  m public.matches;
begin
  select * into m from public.matches where id = p_match_id;

  if not (public.can_captain(m.team_id) or public.can_edit_team(m.team_id)) then
    raise exception 'No tienes permiso sobre este partido' using errcode = '42501';
  end if;
  if m.status <> 'live' or m.started_at is null then
    raise exception 'El partido no está en juego' using errcode = '23514';
  end if;
  if m.descanso_at is not null then
    raise exception 'Ya fueron al descanso' using errcode = '23514';
  end if;

  update public.matches set descanso_at = now()
  where id = p_match_id returning * into m;
  return m;
end;
$$;

create or replace function public.iniciar_segundo_tiempo(p_match_id uuid)
returns public.matches
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  m public.matches;
begin
  select * into m from public.matches where id = p_match_id;

  if not (public.can_captain(m.team_id) or public.can_edit_team(m.team_id)) then
    raise exception 'No tienes permiso sobre este partido' using errcode = '42501';
  end if;
  if m.descanso_at is null then
    raise exception 'Primero hay que ir al descanso' using errcode = '23514';
  end if;
  if m.segundo_tiempo_at is not null then
    raise exception 'El segundo tiempo ya empezó' using errcode = '23514';
  end if;

  update public.matches set segundo_tiempo_at = now()
  where id = p_match_id returning * into m;
  return m;
end;
$$;

create or replace function public.finalizar_partido(
  p_match_id  uuid,
  p_agregados int default 0
)
returns public.matches
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  m public.matches;
begin
  select * into m from public.matches where id = p_match_id;

  if not (public.can_captain(m.team_id) or public.can_edit_team(m.team_id)) then
    raise exception 'No tienes permiso sobre este partido' using errcode = '42501';
  end if;
  if m.status <> 'live' then
    raise exception 'El partido no está en juego' using errcode = '23514';
  end if;

  update public.matches
  set status = 'finished',
      ended_at = now(),
      minutos_agregados = greatest(0, coalesce(p_agregados, 0))
  where id = p_match_id
  returning * into m;

  -- Un reto que termina en partido jugado se cierra también.
  update public.challenges set status = 'played', updated_at = now()
  where match_id = p_match_id and status = 'accepted';

  return m;
end;
$$;

grant execute on function public.iniciar_partido(uuid)         to authenticated;
grant execute on function public.ir_al_descanso(uuid)          to authenticated;
grant execute on function public.iniciar_segundo_tiempo(uuid)  to authenticated;
grant execute on function public.finalizar_partido(uuid, int)  to authenticated;

-- ---------------------------------------------------------------------
-- 4. El gol toma el minuto del reloj
-- ---------------------------------------------------------------------
-- Si no se dice el minuto y el partido está corriendo, lo pone el reloj.
-- Nadie tiene que mirar el celular y calcular en qué minuto va.
create or replace function public.log_goal(
  p_match_id  uuid,
  p_player_id uuid              default null,
  p_minute    smallint          default null,
  p_side      public.team_side  default 'us',
  p_assist_player_id uuid       default null,
  p_is_own_goal boolean         default false
)
returns public.match_events
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_team_id uuid;
  v_estado  public.match_status;
  v_minuto  smallint := p_minute;
  v_event   public.match_events;
begin
  select team_id, status into v_team_id, v_estado
  from public.matches where id = p_match_id;

  if v_team_id is null then
    raise exception 'El partido no existe' using errcode = 'P0002';
  end if;

  if v_minuto is null and v_estado = 'live' then
    v_minuto := public.minuto_actual(p_match_id)::smallint;
  end if;

  insert into public.match_events (
    match_id, team_id, player_id, assist_player_id,
    type, side, minute, is_own_goal, created_by
  )
  values (
    p_match_id, v_team_id, p_player_id, p_assist_player_id,
    'goal', p_side, v_minuto, p_is_own_goal, auth.uid()
  )
  returning * into v_event;

  return v_event;
end;
$$;

grant execute on function public.log_goal(uuid, uuid, smallint, public.team_side, uuid, boolean)
  to authenticated;

-- ---------------------------------------------------------------------
-- 5. El partido en vivo, con su reloj
-- ---------------------------------------------------------------------
drop view if exists public.partido_en_vivo;
create view public.partido_en_vivo
with (security_invoker = true)
as
select
  m.id,
  m.team_id,
  m.opponent_team_id,
  t.name            as equipo,
  m.opponent_name   as rival,
  m.team_score,
  m.opponent_score,
  m.is_home,
  m.venue,
  m.kickoff_at,
  m.duration_minutes,
  m.substitutions_allowed,
  m.started_at,
  m.descanso_at,
  m.segundo_tiempo_at,
  m.ended_at,
  m.minutos_agregados,
  public.minuto_actual(m.id) as minuto,
  case
    when m.ended_at is not null                                    then 'terminado'
    when m.descanso_at is not null and m.segundo_tiempo_at is null then 'descanso'
    when m.segundo_tiempo_at is not null                           then 'segundo_tiempo'
    when m.started_at is not null                                  then 'primer_tiempo'
    when now() >= m.kickoff_at - interval '30 minutes'             then 'listo_para_empezar'
    else 'esperando'
  end as fase
from public.matches m
join public.teams t on t.id = m.team_id
where m.status in ('scheduled', 'live');

grant select on public.partido_en_vivo to anon, authenticated;

comment on view public.partido_en_vivo is
  'El partido con su reloj y su fase. "listo_para_empezar" aparece 30 min antes de la hora acordada.';

-- ---------------------------------------------------------------------
-- 6. Partidos que ya deberían haber empezado
-- ---------------------------------------------------------------------
-- Para avisarle al capitán, en vez de que el partido se quede olvidado
-- en "programado" para siempre.
create or replace function public.partidos_por_empezar(p_team_id uuid)
returns table (
  id            uuid,
  rival         text,
  kickoff_at    timestamptz,
  minutos_tarde int,
  venue         text
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    m.id,
    m.opponent_name,
    m.kickoff_at,
    greatest(0, floor(extract(epoch from (now() - m.kickoff_at)) / 60)::int),
    m.venue
  from public.matches m
  where (m.team_id = p_team_id or m.opponent_team_id = p_team_id)
    and m.status = 'scheduled'
    and now() >= m.kickoff_at - interval '30 minutes'
    and public.can_view_team(m.team_id)
  order by m.kickoff_at;
$$;

grant execute on function public.partidos_por_empezar(uuid) to authenticated;
