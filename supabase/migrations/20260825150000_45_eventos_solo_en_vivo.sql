-- =====================================================================
-- Anotar Gol - 45 | Los eventos solo se registran con el partido en vivo
-- =====================================================================
-- Un gol o una tarjeta pertenecen a un partido que se está jugando. Que
-- se pudieran meter sobre un partido programado —o sobre uno terminado
-- hace tres semanas— dejaba el historial sin defensa.
--
-- La regla se pone en RLS, no en la app: `log_goal` NO es security
-- definer, así que la política le aplica igual que a un insert directo.
-- Una sola regla, un solo lugar.
--
-- CUIDADO, y por eso esta migración trae más cosas: la regla sola dejaba
-- el marcador inservible. `iniciar_partido()` existía desde la 29 pero
-- NADIE la llamaba, así que ningún partido podía llegar nunca a 'live' y
-- ningún gol se habría podido registrar jamás. Una regla que no se puede
-- cumplir no es una regla, es un candado sin llave. Aquí se añade lo que
-- faltaba para que la app pueda abrirlo.
--
-- Se añaden además:
--   * `p_rival_player_id` en log_goal. `match_events` ya tenía la
--     columna y la vista `goleadores` ya tenía una rama entera para los
--     goleadores rivales, pero no había forma de llenarla.
--   * `log_tarjeta`, para que las tarjetas entren por el mismo camino
--     que los goles en vez de por un insert suelto.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Solo se registran eventos de un partido en juego
-- ---------------------------------------------------------------------
drop policy if exists match_events_insert on public.match_events;
create policy match_events_insert on public.match_events
  for insert to authenticated
  with check (
    public.can_edit_team(team_id)
    and exists (
      select 1
      from public.matches m
      where m.id = match_events.match_id
        and m.team_id = match_events.team_id
        and m.status = 'live'
    )
  );

-- ---------------------------------------------------------------------
-- 2. El gol puede ser de un jugador rival
-- ---------------------------------------------------------------------
-- Se BORRA la firma vieja antes de crear la nueva. Todos los parámetros
-- tienen valor por defecto, así que dejar las dos convivir haría que
-- llamar por nombre —como llama PostgREST— fallara con "function is not
-- unique". Una sobrecarga con defaults no es una sobrecarga: es una
-- ambigüedad esperando a que alguien la pise.
drop function if exists public.log_goal(uuid, uuid, smallint, public.team_side, uuid, boolean);

create or replace function public.log_goal(
  p_match_id         uuid,
  p_player_id        uuid              default null,
  p_minute           smallint          default null,
  p_side             public.team_side  default 'us',
  p_assist_player_id uuid              default null,
  p_is_own_goal      boolean           default false,
  p_rival_player_id  uuid              default null
)
returns public.match_events
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_team_id uuid;
  v_estado  public.match_status;
  v_minuto  smallint := p_minute;
  v_evento  public.match_events;
begin
  select team_id, status into v_team_id, v_estado
  from public.matches where id = p_match_id;

  if v_team_id is null then
    raise exception 'Ese partido no existe' using errcode = 'P0002';
  end if;

  -- Un gol nuestro no puede ser de un jugador rival, ni al revés.
  if p_side = 'us' and p_rival_player_id is not null then
    raise exception 'Un gol propio no puede ser de un jugador rival'
      using errcode = '23514';
  end if;
  if p_side = 'them' and p_player_id is not null then
    raise exception 'Un gol del rival no puede ser de un jugador nuestro'
      using errcode = '23514';
  end if;

  -- Si no se dice el minuto y el partido está en juego, se toma del reloj.
  if v_minuto is null and v_estado = 'live' then
    v_minuto := public.minuto_actual(p_match_id)::smallint;
  end if;

  insert into public.match_events (
    match_id, team_id, player_id, rival_player_id, assist_player_id,
    type, side, minute, is_own_goal, created_by
  )
  values (
    p_match_id, v_team_id, p_player_id, p_rival_player_id, p_assist_player_id,
    'goal', p_side, v_minuto, p_is_own_goal, auth.uid()
  )
  returning * into v_evento;

  return v_evento;
end;
$$;

revoke all on function public.log_goal(uuid, uuid, smallint, public.team_side, uuid, boolean, uuid) from public;
grant execute on function public.log_goal(uuid, uuid, smallint, public.team_side, uuid, boolean, uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 3. Las tarjetas, por el mismo camino
-- ---------------------------------------------------------------------
create or replace function public.log_tarjeta(
  p_match_id        uuid,
  p_tipo            public.match_event_type,
  p_player_id       uuid             default null,
  p_side            public.team_side default 'us',
  p_rival_player_id uuid             default null,
  p_minute          smallint         default null
)
returns public.match_events
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_team_id uuid;
  v_estado  public.match_status;
  v_minuto  smallint := p_minute;
  v_evento  public.match_events;
begin
  if p_tipo not in ('yellow_card', 'red_card') then
    raise exception 'Esto no es una tarjeta' using errcode = '23514';
  end if;

  select team_id, status into v_team_id, v_estado
  from public.matches where id = p_match_id;

  if v_team_id is null then
    raise exception 'Ese partido no existe' using errcode = 'P0002';
  end if;

  if v_minuto is null and v_estado = 'live' then
    v_minuto := public.minuto_actual(p_match_id)::smallint;
  end if;

  insert into public.match_events (
    match_id, team_id, player_id, rival_player_id,
    type, side, minute, created_by
  )
  values (
    p_match_id, v_team_id, p_player_id, p_rival_player_id,
    p_tipo, p_side, v_minuto, auth.uid()
  )
  returning * into v_evento;

  return v_evento;
end;
$$;

revoke all on function public.log_tarjeta(uuid, public.match_event_type, uuid, public.team_side, uuid, smallint) from public;
grant execute on function public.log_tarjeta(uuid, public.match_event_type, uuid, public.team_side, uuid, smallint) to authenticated;

comment on function public.log_tarjeta is
  'Registra una tarjeta. Como el gol, exige que el partido esté en vivo (RLS).';
