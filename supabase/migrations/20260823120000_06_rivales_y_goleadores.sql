-- =====================================================================
-- Anotar Gol - 06 | Rivales, plantillas imaginarias y goleadores
-- =====================================================================
-- Tres cosas:
--
--   1. Cualquier integrante del club (no solo el cuerpo tecnico) puede
--      editar la plantilla: nombres, dorsales y posiciones.
--   2. El rival deja de ser un texto suelto en `matches.opponent_name` y
--      pasa a poder tener plantilla propia. Y si no se conocen sus
--      jugadores, se generan inventados, marcados como tales.
--   3. Vistas de goleadores e historial de goles.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Quien puede tocar la plantilla
-- ---------------------------------------------------------------------
-- `can_edit_team` (owner/admin/coach) sigue mandando sobre partidos y
-- eventos. Para la plantilla se abre a cualquier miembro con rol, porque
-- el equipo se administra entre todos. El hincha y el anonimo siguen
-- fuera.
create or replace function public.can_edit_squad(p_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    public.team_role_of(p_team_id) in ('owner', 'admin', 'coach', 'player'),
    false);
$$;

grant execute on function public.can_edit_squad(uuid) to anon, authenticated;

drop policy if exists players_insert on public.players;
create policy players_insert on public.players
  for insert to authenticated
  with check (public.can_edit_squad(team_id));

drop policy if exists players_update on public.players;
create policy players_update on public.players
  for update to authenticated
  using (public.can_edit_squad(team_id))
  with check (public.can_edit_squad(team_id));

-- Borrar un jugador arrastra sus eventos: eso sigue siendo del staff.
drop policy if exists players_delete on public.players;
create policy players_delete on public.players
  for delete to authenticated
  using (public.can_edit_team(team_id));

-- ---------------------------------------------------------------------
-- 2. Rivales
-- ---------------------------------------------------------------------
-- Un rival pertenece al club que lo registra: cada club lleva su propia
-- libreta de equipos contrarios y no ve la de los demas.
create table if not exists public.rivals (
  id         uuid primary key default gen_random_uuid(),
  team_id    uuid not null references public.teams (id) on delete cascade,
  name       text not null check (char_length(btrim(name)) between 2 and 80),
  logo_url   text,
  notes      text,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (team_id, name),
  unique (id, team_id)
);

create index if not exists rivals_team_idx on public.rivals (team_id);

comment on table public.rivals is
  'Equipos contrarios registrados por un club. Se reutilizan entre partidos.';

-- Jugadores del rival. Misma forma que `players`, mas la bandera que
-- distingue lo real de lo inventado.
create table if not exists public.rival_players (
  id              uuid primary key default gen_random_uuid(),
  rival_id        uuid not null,
  team_id         uuid not null,
  number          smallint check (number between 1 and 99),
  full_name       text not null check (char_length(btrim(full_name)) >= 2),
  position        public.player_position not null default 'MF',
  position_detail text,
  -- true = el nombre no es real, se genero por falta de informacion.
  -- La app SIEMPRE tiene que mostrarlo; si no, son datos falsos
  -- presentados como ciertos.
  is_imaginary    boolean not null default false,
  is_active       boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (id, team_id),
  foreign key (rival_id, team_id)
    references public.rivals (id, team_id) on delete cascade
);

create index if not exists rival_players_rival_idx on public.rival_players (rival_id);

create unique index if not exists rival_players_number_uniq
  on public.rival_players (rival_id, number) where is_active and number is not null;

comment on column public.rival_players.is_imaginary is
  'true = jugador inventado por falta de datos del rival. Debe verse en la interfaz.';

-- El partido puede apuntar a un rival con plantilla. `opponent_name` se
-- conserva: hay partidos contra equipos que nunca se registran.
alter table public.matches
  add column if not exists rival_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'matches_rival_fk'
  ) then
    alter table public.matches
      add constraint matches_rival_fk
      foreign key (rival_id, team_id)
      references public.rivals (id, team_id) on delete set null;
  end if;
end
$$;

-- Un gol del rival ahora puede tener autor.
alter table public.match_events
  add column if not exists rival_player_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'match_events_rival_player_fk'
  ) then
    alter table public.match_events
      add constraint match_events_rival_player_fk
      foreign key (rival_player_id, team_id)
      references public.rival_players (id, team_id) on delete set null;
  end if;

  -- Un jugador del rival solo puede figurar en un evento del rival.
  if not exists (
    select 1 from pg_constraint where conname = 'match_events_rival_side_chk'
  ) then
    alter table public.match_events
      add constraint match_events_rival_side_chk
      check (side = 'them' or rival_player_id is null);
  end if;
end
$$;

create index if not exists match_events_rival_player_idx
  on public.match_events (rival_player_id);

-- ---------------------------------------------------------------------
-- 3. RLS de las tablas nuevas
-- ---------------------------------------------------------------------
alter table public.rivals        enable row level security;
alter table public.rival_players enable row level security;

do $$
declare
  t text;
begin
  foreach t in array array['rivals', 'rival_players']
  loop
    execute format('drop policy if exists %I on public.%I', t || '_select', t);
    execute format($fmt$
      create policy %I on public.%I
        for select to anon, authenticated
        using (public.can_view_team(team_id))
    $fmt$, t || '_select', t);

    execute format('drop policy if exists %I on public.%I', t || '_insert', t);
    execute format($fmt$
      create policy %I on public.%I
        for insert to authenticated
        with check (public.can_edit_squad(team_id))
    $fmt$, t || '_insert', t);

    execute format('drop policy if exists %I on public.%I', t || '_update', t);
    execute format($fmt$
      create policy %I on public.%I
        for update to authenticated
        using (public.can_edit_squad(team_id))
        with check (public.can_edit_squad(team_id))
    $fmt$, t || '_update', t);

    execute format('drop policy if exists %I on public.%I', t || '_delete', t);
    execute format($fmt$
      create policy %I on public.%I
        for delete to authenticated
        using (public.can_edit_squad(team_id))
    $fmt$, t || '_delete', t);
  end loop;
end
$$;

-- ---------------------------------------------------------------------
-- 4. Generador de plantilla imaginaria
-- ---------------------------------------------------------------------
-- El caso de uso: vas a jugar contra un equipo del que no sabes ni los
-- nombres. En vez de dejar la pantalla vacia, se arma un 4-3-3 con
-- nombres inventados y TODOS marcados con is_imaginary = true.
--
-- SECURITY INVOKER a proposito: es RLS quien decide si puedes escribir
-- en ese club, no esta funcion.
create or replace function public.generar_plantilla_imaginaria(
  p_rival_id uuid,
  p_cantidad int default 11
)
returns setof public.rival_players
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_team_id uuid;
  v_nombres text[] := array[
    'Andrés','Bryan','Carlos','Damián','Erick','Fabián','Gabriel','Héctor',
    'Iván','Jefferson','Kevin','Luis','Marco','Nicolás','Óscar','Patricio',
    'Ramiro','Santiago','Tomás','Ulises','Vinicio','Washington','Xavier','Yuri'];
  v_apellidos text[] := array[
    'Andrade','Bermúdez','Cedeño','Delgado','Espinoza','Franco','Guerrero',
    'Hurtado','Intriago','Jaramillo','Lucas','Montero','Nazareno','Ortega',
    'Ponce','Quiñónez','Reasco','Solís','Tenorio','Uribe','Vargas','Zambrano'];
  v_posiciones public.player_position[] := array[
    'GK','DF','DF','DF','DF','MF','MF','MF','FW','FW','FW']::public.player_position[];
  v_detalles text[] := array[
    'Portero','Lateral Derecho','Defensa Central','Defensa Central','Lateral Izquierdo',
    'Mediocampista Defensivo','Mediocampista Central','Mediocampista Ofensivo',
    'Extremo Derecho','Delantero Centro','Extremo Izquierdo'];
  i int;
begin
  select r.team_id into v_team_id from public.rivals r where r.id = p_rival_id;

  if v_team_id is null then
    raise exception 'El rival no existe' using errcode = 'P0002';
  end if;

  -- Entre 1 y 11. Pedir 50 jugadores no tiene sentido en una cancha.
  p_cantidad := least(greatest(coalesce(p_cantidad, 11), 1), 11);

  -- Re-generable: se borran los inventados anteriores, nunca los reales
  -- que alguien haya cargado a mano.
  delete from public.rival_players
  where rival_id = p_rival_id and is_imaginary;

  for i in 1..p_cantidad loop
    insert into public.rival_players (
      rival_id, team_id, number, full_name, position, position_detail, is_imaginary
    )
    values (
      p_rival_id,
      v_team_id,
      i,
      v_nombres[1 + floor(random() * array_length(v_nombres, 1))::int] || ' ' ||
      v_apellidos[1 + floor(random() * array_length(v_apellidos, 1))::int],
      v_posiciones[i],
      v_detalles[i],
      true
    )
    on conflict do nothing;
  end loop;

  return query
    select * from public.rival_players rp
    where rp.rival_id = p_rival_id
    order by rp.number nulls last;
end;
$$;

grant execute on function public.generar_plantilla_imaginaria(uuid, int) to authenticated;

-- Crea el rival y, en el mismo paso, le inventa la plantilla. Es el
-- atajo para "no tengo los datos del otro equipo".
create or replace function public.crear_rival_con_plantilla(
  p_team_id  uuid,
  p_nombre   text,
  p_inventar boolean default true,
  p_cantidad int default 11
)
returns public.rivals
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_rival public.rivals;
begin
  insert into public.rivals (team_id, name, created_by)
  values (p_team_id, btrim(p_nombre), auth.uid())
  on conflict (team_id, name) do update set updated_at = now()
  returning * into v_rival;

  if p_inventar then
    perform public.generar_plantilla_imaginaria(v_rival.id, p_cantidad);
  end if;

  return v_rival;
end;
$$;

grant execute on function public.crear_rival_con_plantilla(uuid, text, boolean, int)
  to authenticated;

-- ---------------------------------------------------------------------
-- 5. Goleadores e historial
-- ---------------------------------------------------------------------
-- Ranking de quien mete goles, del club y de los rivales. `bando`
-- permite a la app mostrar una tabla, la otra, o las dos.
drop view if exists public.goleadores;
create view public.goleadores
with (security_invoker = true)
as
select
  'nuestro'::text        as bando,
  p.team_id,
  p.id                   as jugador_id,
  p.full_name            as nombre,
  p.number               as dorsal,
  p.position,
  false                  as es_imaginario,
  null::text             as club,
  count(*)               as goles,
  min(e.created_at)      as primer_gol,
  max(e.created_at)      as ultimo_gol
from public.match_events e
join public.players p on p.id = e.player_id
where e.type = 'goal' and not e.is_own_goal
group by p.team_id, p.id, p.full_name, p.number, p.position

union all

select
  'rival'::text,
  rp.team_id,
  rp.id,
  rp.full_name,
  rp.number,
  rp.position,
  rp.is_imaginary,
  r.name,
  count(*),
  min(e.created_at),
  max(e.created_at)
from public.match_events e
join public.rival_players rp on rp.id = e.rival_player_id
join public.rivals r on r.id = rp.rival_id
where e.type = 'goal' and not e.is_own_goal
group by rp.team_id, rp.id, rp.full_name, rp.number, rp.position, rp.is_imaginary, r.name;

comment on view public.goleadores is
  'Ranking de goleadores del club y de los rivales. Ordenar por goles desc.';

-- Historial: un gol por fila, con quien lo metio y en que partido.
drop view if exists public.historial_goles;
create view public.historial_goles
with (security_invoker = true)
as
select
  e.id,
  e.team_id,
  e.match_id,
  e.minute,
  e.side,
  e.is_own_goal,
  e.created_at,
  coalesce(p.full_name, rp.full_name)     as goleador,
  coalesce(p.number, rp.number)           as dorsal,
  coalesce(rp.is_imaginary, false)        as es_imaginario,
  asis.full_name                          as asistencia,
  m.opponent_name,
  m.kickoff_at,
  m.status,
  m.is_home
from public.match_events e
join public.matches m on m.id = e.match_id
left join public.players p        on p.id  = e.player_id
left join public.players asis     on asis.id = e.assist_player_id
left join public.rival_players rp  on rp.id = e.rival_player_id
where e.type = 'goal';

comment on view public.historial_goles is
  'Un gol por fila, con autor, asistencia y partido. Ordenar por created_at desc.';

grant select on public.goleadores       to anon, authenticated;
grant select on public.historial_goles  to anon, authenticated;

-- ---------------------------------------------------------------------
-- 6. Tiempo real y updated_at
-- ---------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['rivals', 'rival_players']
  loop
    execute format('drop trigger if exists set_updated_at on public.%I', t);
    execute format(
      'create trigger set_updated_at before update on public.%I
       for each row execute function public.set_updated_at()', t);
  end loop;

  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public' and tablename = 'rival_players'
     ) then
    alter publication supabase_realtime add table public.rival_players;
  end if;
end
$$;

alter table public.rival_players replica identity full;
