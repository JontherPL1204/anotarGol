-- =====================================================================
-- Anotar Gol - esquema completo (archivo GENERADO)
-- =====================================================================
-- Concatenacion de supabase/migrations/*.sql en orden.
-- Pensado para pegarlo de una sola vez en el SQL Editor de Supabase.
-- NO edites este archivo: edita las migraciones y regeneralo.
--
-- Orden incluido:
--   20260821120000_00_extensions_enums.sql
--   20260821120100_01_core_schema.sql
--   20260821120200_02_functions_triggers.sql
--   20260821120300_03_views.sql
--   20260821120400_04_rls.sql
--   20260821120500_05_realtime_storage.sql
-- =====================================================================

-- #####################################################################
-- # 20260821120000_00_extensions_enums.sql
-- #####################################################################

-- =====================================================================
-- Anotar Gol - 00 | Extensiones y tipos enumerados
-- =====================================================================
-- Se ejecuta primero. Define el vocabulario del dominio como ENUMs de
-- Postgres para que la base rechace valores invalidos (ej. status = "xyz")
-- en lugar de confiar en que el cliente Flutter mande el texto correcto.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- Idempotente: si la migracion se corre dos veces, no falla.
do $$
begin
  -- Rol de una persona DENTRO de un equipo (no es un rol global de la app).
  if not exists (select 1 from pg_type where typname = 'team_role') then
    create type public.team_role as enum ('owner', 'admin', 'coach', 'player', 'viewer');
  end if;

  -- Ciclo de vida de un partido.
  if not exists (select 1 from pg_type where typname = 'match_status') then
    create type public.match_status as enum ('scheduled', 'live', 'finished', 'postponed', 'cancelled');
  end if;

  -- Eventos que ocurren dentro de un partido.
  -- Nota: la asistencia NO es un tipo de evento, es la columna
  -- assist_player_id sobre el evento 'goal' (evita datos duplicados).
  if not exists (select 1 from pg_type where typname = 'match_event_type') then
    create type public.match_event_type as enum (
      'goal',
      'yellow_card',
      'red_card',
      'penalty_missed',
      'substitution_in',
      'substitution_out',
      'note'
    );
  end if;

  -- A que lado pertenece el evento: nuestro equipo o el rival.
  if not exists (select 1 from pg_type where typname = 'team_side') then
    create type public.team_side as enum ('us', 'them');
  end if;

  -- Posicion normalizada. El texto libre ("Lateral Derecho") vive en
  -- players.position_detail para no perder el detalle actual de la app.
  if not exists (select 1 from pg_type where typname = 'player_position') then
    create type public.player_position as enum ('GK', 'DF', 'MF', 'FW');
  end if;
end
$$;


-- #####################################################################
-- # 20260821120100_01_core_schema.sql
-- #####################################################################

-- =====================================================================
-- Anotar Gol - 01 | Esquema principal
-- =====================================================================
-- Modelo multi-equipo: una persona puede pertenecer a varios equipos y
-- tener un rol distinto en cada uno. Por eso el rol vive en team_members
-- y NO en la tabla de usuarios (limitacion del modelo original del plan).
-- =====================================================================

-- ---------------------------------------------------------------------
-- profiles: espejo publico de auth.users (auth.users no se lee directo)
-- ---------------------------------------------------------------------
create table if not exists public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  email        text,
  avatar_url   text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

comment on table public.profiles is
  'Datos publicos del usuario. Se crea automaticamente via trigger al registrarse.';

-- ---------------------------------------------------------------------
-- teams: el club
-- ---------------------------------------------------------------------
create table if not exists public.teams (
  id                uuid primary key default gen_random_uuid(),
  name              text not null check (char_length(btrim(name)) between 2 and 80),
  short_name        text check (char_length(btrim(short_name)) between 1 and 12),
  slug              text unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  primary_color     text not null default '#1B5E20' check (primary_color ~* '^#[0-9a-f]{6}$'),
  secondary_color   text not null default '#FFD700' check (secondary_color ~* '^#[0-9a-f]{6}$'),
  logo_url          text,
  -- is_public = true habilita el "marcador para el hincha": cualquiera
  -- puede LEER sin loguearse, pero solo el staff puede escribir.
  is_public         boolean not null default true,
  created_by        uuid references auth.users (id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

comment on column public.teams.is_public is
  'true = cualquiera (incluso sin login) puede leer plantilla, partidos y marcador.';

-- ---------------------------------------------------------------------
-- team_members: quien pertenece a que equipo y con que rol
-- ---------------------------------------------------------------------
create table if not exists public.team_members (
  team_id    uuid not null references public.teams (id) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  role       public.team_role not null default 'viewer',
  created_at timestamptz not null default now(),
  primary key (team_id, user_id)
);

create index if not exists team_members_user_idx on public.team_members (user_id);

-- ---------------------------------------------------------------------
-- seasons: temporadas
-- ---------------------------------------------------------------------
-- Faltaba en el plan. Sin temporada, las estadisticas historicas se
-- mezclan entre anios y no hay forma de decir "goles de esta temporada".
create table if not exists public.seasons (
  id         uuid primary key default gen_random_uuid(),
  team_id    uuid not null references public.teams (id) on delete cascade,
  name       text not null check (char_length(btrim(name)) between 2 and 40),
  starts_on  date,
  ends_on    date,
  is_current boolean not null default false,
  created_at timestamptz not null default now(),
  unique (team_id, name),
  check (starts_on is null or ends_on is null or ends_on >= starts_on)
);

-- Solo una temporada actual por equipo.
create unique index if not exists seasons_one_current_per_team
  on public.seasons (team_id) where is_current;

-- ---------------------------------------------------------------------
-- players: la plantilla (hoy quemada dentro de plantilla.dart)
-- ---------------------------------------------------------------------
create table if not exists public.players (
  id              uuid primary key default gen_random_uuid(),
  team_id         uuid not null references public.teams (id) on delete cascade,
  number          smallint check (number between 1 and 99),
  full_name       text not null check (char_length(btrim(full_name)) >= 2),
  position        public.player_position not null default 'MF',
  -- Conserva el texto actual de la app: 'Lateral Derecho', 'Mediocampista Ofensivo'...
  position_detail text,
  photo_url       text,
  birth_date      date,
  is_active       boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  -- Necesario para las llaves foraneas compuestas de match_events / lineups.
  unique (id, team_id)
);

create index if not exists players_team_idx on public.players (team_id, is_active);

-- Dos jugadores activos no pueden compartir dorsal en el mismo equipo.
create unique index if not exists players_team_active_number_uniq
  on public.players (team_id, number) where is_active and number is not null;

-- ---------------------------------------------------------------------
-- matches: partidos
-- ---------------------------------------------------------------------
-- Decision de modelado: el plan proponia home_score/away_score, que es
-- ambiguo cuando el equipo juega de visitante (?cual de los dos es el
-- nuestro?). Aca el marcador se guarda SIEMPRE desde la perspectiva del
-- equipo (team_score / opponent_score) mas la bandera is_home.
-- La vista match_summary traduce eso a local/visitante para la UI.
create table if not exists public.matches (
  id                uuid primary key default gen_random_uuid(),
  team_id           uuid not null references public.teams (id) on delete cascade,
  season_id         uuid references public.seasons (id) on delete set null,
  opponent_name     text not null check (char_length(btrim(opponent_name)) >= 2),
  opponent_logo_url text,
  kickoff_at        timestamptz not null,
  venue             text,
  competition       text,
  is_home           boolean not null default true,
  status            public.match_status not null default 'scheduled',
  -- Estos dos NO se escriben a mano desde la app: los recalcula un
  -- trigger a partir de match_events (ver migracion 02).
  team_score        smallint not null default 0 check (team_score >= 0),
  opponent_score    smallint not null default 0 check (opponent_score >= 0),
  notes             text,
  created_by        uuid references auth.users (id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (id, team_id)
);

comment on column public.matches.team_score is
  'Derivado de match_events por trigger. No escribir directamente.';

create index if not exists matches_team_kickoff_idx on public.matches (team_id, kickoff_at desc);
create index if not exists matches_team_status_idx  on public.matches (team_id, status);
create index if not exists matches_season_idx       on public.matches (season_id);

-- ---------------------------------------------------------------------
-- match_events: el gol deja de ser un contador y pasa a ser historia
-- ---------------------------------------------------------------------
create table if not exists public.match_events (
  id               uuid primary key default gen_random_uuid(),
  match_id         uuid not null,
  -- Desnormalizado a proposito: permite que RLS filtre por equipo sin
  -- hacer JOIN contra matches en cada fila leida.
  team_id          uuid not null,
  player_id        uuid,
  assist_player_id uuid,
  type             public.match_event_type not null,
  side             public.team_side not null default 'us',
  minute           smallint check (minute between 0 and 130),
  is_own_goal      boolean not null default false,
  description      text,
  created_by       uuid references auth.users (id) on delete set null,
  created_at       timestamptz not null default now(),

  -- El evento pertenece al partido Y al equipo de ese partido: es
  -- imposible colgar un evento de un partido de otro club.
  foreign key (match_id, team_id)
    references public.matches (id, team_id) on delete cascade,
  -- El goleador debe ser jugador de ESE equipo.
  foreign key (player_id, team_id)
    references public.players (id, team_id) on delete set null,
  foreign key (assist_player_id, team_id)
    references public.players (id, team_id) on delete set null,

  -- Los jugadores del rival no estan en nuestra plantilla.
  check (side = 'us' or player_id is null),
  check (side = 'us' or assist_player_id is null),
  -- Solo un gol puede ser en propia puerta.
  check (not is_own_goal or type = 'goal'),
  -- Nadie se asiste a si mismo.
  check (assist_player_id is null or assist_player_id is distinct from player_id),
  -- La asistencia solo tiene sentido en un gol legitimo.
  check (assist_player_id is null or (type = 'goal' and not is_own_goal))
);

create index if not exists match_events_match_idx  on public.match_events (match_id, minute);
create index if not exists match_events_player_idx on public.match_events (player_id);
create index if not exists match_events_team_idx   on public.match_events (team_id);

-- ---------------------------------------------------------------------
-- match_lineups: convocatoria / once inicial por partido
-- ---------------------------------------------------------------------
-- Faltaba en el plan. Sin esta tabla no existe el concepto de "partidos
-- jugados" y las estadisticas por jugador quedan a medias.
create table if not exists public.match_lineups (
  match_id       uuid not null,
  player_id      uuid not null,
  team_id        uuid not null,
  is_starter     boolean not null default true,
  shirt_number   smallint check (shirt_number between 1 and 99),
  position       public.player_position,
  minutes_played smallint check (minutes_played between 0 and 130),
  created_at     timestamptz not null default now(),
  primary key (match_id, player_id),
  foreign key (match_id, team_id)
    references public.matches (id, team_id) on delete cascade,
  foreign key (player_id, team_id)
    references public.players (id, team_id) on delete cascade
);

create index if not exists match_lineups_player_idx on public.match_lineups (player_id);

-- ---------------------------------------------------------------------
-- team_settings: preferencias por equipo
-- ---------------------------------------------------------------------
create table if not exists public.team_settings (
  team_id                uuid primary key references public.teams (id) on delete cascade,
  theme                  text not null default 'system'
                           check (theme in ('system', 'light', 'dark')),
  default_screen         text not null default 'home',
  offline_mode           boolean not null default true,
  match_duration_minutes smallint not null default 90
                           check (match_duration_minutes between 10 and 130),
  updated_at             timestamptz not null default now()
);


-- #####################################################################
-- # 20260821120200_02_functions_triggers.sql
-- #####################################################################

-- =====================================================================
-- Anotar Gol - 02 | Funciones, triggers y RPC
-- =====================================================================
-- Aca vive la logica que la app NO debe reimplementar en Dart:
--   * el marcador se deriva de los eventos (una sola fuente de verdad)
--   * el perfil se crea solo al registrarse
--   * quien crea un equipo queda como owner automaticamente
--   * las funciones de permisos que usara RLS en la migracion 04
-- Todas las funciones fijan search_path para evitar secuestro de esquema.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Utilidades
-- ---------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- Convierte 'Pasion Futbolera FC' -> 'pasion-futbolera-fc' (sin depender
-- de la extension unaccent, que no viene activa por defecto).
create or replace function public.slugify(p_text text)
returns text
language sql
immutable
strict
as $$
  select btrim(
    regexp_replace(
      lower(
        translate(
          p_text,
          'áéíóúàèìòùäëïöüâêîôûñçÁÉÍÓÚÀÈÌÒÙÄËÏÖÜÂÊÎÔÛÑÇ',
          'aeiouaeiouaeiouaeiouncAEIOUAEIOUAEIOUAEIOUNC'
        )
      ),
      '[^a-z0-9]+', '-', 'g'
    ),
    '-'
  );
$$;

-- ---------------------------------------------------------------------
-- Funciones de permisos
-- ---------------------------------------------------------------------
-- IMPORTANTE: son SECURITY DEFINER a proposito. Si una politica RLS de
-- team_members consultara team_members directamente, Postgres entraria en
-- recursion infinita. Al leerla desde una funcion definer, RLS no se
-- vuelve a evaluar y el problema desaparece.

create or replace function public.team_role_of(p_team_id uuid)
returns public.team_role
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select tm.role
  from public.team_members tm
  where tm.team_id = p_team_id
    and tm.user_id = auth.uid();
$$;

create or replace function public.is_team_member(p_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.team_members tm
    where tm.team_id = p_team_id
      and tm.user_id = auth.uid()
  );
$$;

-- Lectura: el equipo es publico, o soy miembro.
create or replace function public.can_view_team(p_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.teams t
    where t.id = p_team_id
      and (t.is_public or public.is_team_member(t.id))
  );
$$;

-- Escritura de datos deportivos: cuerpo tecnico hacia arriba.
create or replace function public.can_edit_team(p_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(public.team_role_of(p_team_id) in ('owner', 'admin', 'coach'), false);
$$;

-- Administracion del club (miembros, ajustes, borrar el equipo).
create or replace function public.can_admin_team(p_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(public.team_role_of(p_team_id) in ('owner', 'admin'), false);
$$;

grant execute on function public.team_role_of(uuid)   to anon, authenticated;
grant execute on function public.is_team_member(uuid) to anon, authenticated;
grant execute on function public.can_view_team(uuid)  to anon, authenticated;
grant execute on function public.can_edit_team(uuid)  to anon, authenticated;
grant execute on function public.can_admin_team(uuid) to anon, authenticated;

-- ---------------------------------------------------------------------
-- Perfil automatico al registrarse
-- ---------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.profiles (id, display_name, email, avatar_url)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data ->> 'display_name',
      new.raw_user_meta_data ->> 'full_name',
      split_part(coalesce(new.email, 'hincha'), '@', 1)
    ),
    new.email,
    new.raw_user_meta_data ->> 'avatar_url'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------
-- Quien crea el equipo queda como owner (y se crean sus ajustes)
-- ---------------------------------------------------------------------
-- Sin esto habria un problema del huevo y la gallina: RLS no te deja
-- crear un equipo del que no eres miembro, ni ser miembro de un equipo
-- que todavia no existe.
create or replace function public.handle_new_team()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.created_by is not null then
    insert into public.team_members (team_id, user_id, role)
    values (new.id, new.created_by, 'owner')
    on conflict (team_id, user_id) do update set role = 'owner';
  end if;

  insert into public.team_settings (team_id)
  values (new.id)
  on conflict (team_id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_team_created on public.teams;
create trigger on_team_created
  after insert on public.teams
  for each row execute function public.handle_new_team();

-- ---------------------------------------------------------------------
-- Un equipo nunca puede quedarse sin owner
-- ---------------------------------------------------------------------
create or replace function public.protect_last_owner()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_team_id uuid := coalesce(old.team_id, new.team_id);
  v_owners  int;
begin
  -- Solo importa si estamos quitando o degradando a un owner.
  if old.role <> 'owner' then
    return coalesce(new, old);
  end if;

  -- Si el equipo entero se esta borrando (cascade), no hay nada que proteger.
  if not exists (select 1 from public.teams where id = v_team_id) then
    return coalesce(new, old);
  end if;

  if tg_op = 'UPDATE' and new.role = 'owner' then
    return new;
  end if;

  select count(*) into v_owners
  from public.team_members
  where team_id = v_team_id and role = 'owner';

  if v_owners <= 1 then
    raise exception 'El equipo debe conservar al menos un owner'
      using errcode = '23514';
  end if;

  return coalesce(new, old);
end;
$$;

drop trigger if exists team_members_protect_last_owner on public.team_members;
create trigger team_members_protect_last_owner
  before update or delete on public.team_members
  for each row execute function public.protect_last_owner();

-- ---------------------------------------------------------------------
-- El marcador se deriva de los eventos
-- ---------------------------------------------------------------------
-- Regla de negocio: un gol en propia puerta suma para el rival. Por eso
-- no basta con contar por 'side'.
create or replace function public.recalc_match_score(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.matches m
  set team_score = coalesce(s.team_score, 0),
      opponent_score = coalesce(s.opponent_score, 0)
  from (
    select
      count(*) filter (
        where e.type = 'goal'
          and ((e.side = 'us' and not e.is_own_goal)
            or (e.side = 'them' and e.is_own_goal))
      )::smallint as team_score,
      count(*) filter (
        where e.type = 'goal'
          and ((e.side = 'them' and not e.is_own_goal)
            or (e.side = 'us' and e.is_own_goal))
      )::smallint as opponent_score
    from public.match_events e
    where e.match_id = p_match_id
  ) s
  where m.id = p_match_id;
end;
$$;

create or replace function public.sync_match_score()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'DELETE' then
    perform public.recalc_match_score(old.match_id);
    return old;
  end if;

  perform public.recalc_match_score(new.match_id);

  -- Si el evento se movio de partido, hay que recalcular tambien el viejo.
  if tg_op = 'UPDATE' and old.match_id is distinct from new.match_id then
    perform public.recalc_match_score(old.match_id);
  end if;

  return new;
end;
$$;

drop trigger if exists match_events_sync_score on public.match_events;
create trigger match_events_sync_score
  after insert or update or delete on public.match_events
  for each row execute function public.sync_match_score();

-- ---------------------------------------------------------------------
-- updated_at automatico
-- ---------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['profiles', 'teams', 'players', 'matches', 'team_settings']
  loop
    execute format('drop trigger if exists set_updated_at on public.%I', t);
    execute format(
      'create trigger set_updated_at before update on public.%I
       for each row execute function public.set_updated_at()', t);
  end loop;
end
$$;

-- =====================================================================
-- RPC que consume la app Flutter
-- =====================================================================

-- Crea equipo + membresia owner + ajustes en una sola transaccion.
create or replace function public.create_team(
  p_name            text,
  p_short_name      text default null,
  p_primary_color   text default '#1B5E20',
  p_secondary_color text default '#FFD700',
  p_is_public       boolean default true
)
returns public.teams
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_team      public.teams;
  v_base_slug text;
  v_slug      text;
  v_suffix    int := 0;
begin
  if auth.uid() is null then
    raise exception 'Debes iniciar sesion para crear un equipo'
      using errcode = '42501';
  end if;

  v_base_slug := nullif(public.slugify(p_name), '');
  v_base_slug := coalesce(v_base_slug, 'equipo');
  v_slug := v_base_slug;

  while exists (select 1 from public.teams t where t.slug = v_slug) loop
    v_suffix := v_suffix + 1;
    v_slug := v_base_slug || '-' || v_suffix;
  end loop;

  insert into public.teams (
    name, short_name, slug, primary_color, secondary_color, is_public, created_by
  )
  values (
    btrim(p_name), nullif(btrim(coalesce(p_short_name, '')), ''), v_slug,
    p_primary_color, p_secondary_color, p_is_public, auth.uid()
  )
  returning * into v_team;

  return v_team;
end;
$$;

-- Adopta un equipo que todavia no tiene owner (sirve para tomar el
-- equipo demo creado por seed.sql tras registrarte por primera vez).
create or replace function public.claim_team(p_team_id uuid)
returns public.team_members
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_member public.team_members;
begin
  if auth.uid() is null then
    raise exception 'Debes iniciar sesion' using errcode = '42501';
  end if;

  if exists (
    select 1 from public.team_members
    where team_id = p_team_id and role = 'owner'
  ) then
    raise exception 'Este equipo ya tiene un owner' using errcode = '42501';
  end if;

  if not exists (select 1 from public.teams where id = p_team_id) then
    raise exception 'El equipo no existe' using errcode = 'P0002';
  end if;

  insert into public.team_members (team_id, user_id, role)
  values (p_team_id, auth.uid(), 'owner')
  on conflict (team_id, user_id) do update set role = 'owner'
  returning * into v_member;

  update public.teams
  set created_by = coalesce(created_by, auth.uid())
  where id = p_team_id;

  return v_member;
end;
$$;

-- Atajo para el boton "!CANTAR GOL!": registra el evento y deja que el
-- trigger actualice el marcador. SECURITY INVOKER a proposito, para que
-- RLS siga decidiendo quien puede anotar.
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
  v_event   public.match_events;
begin
  select team_id into v_team_id from public.matches where id = p_match_id;

  if v_team_id is null then
    raise exception 'El partido no existe' using errcode = 'P0002';
  end if;

  insert into public.match_events (
    match_id, team_id, player_id, assist_player_id,
    type, side, minute, is_own_goal, created_by
  )
  values (
    p_match_id, v_team_id, p_player_id, p_assist_player_id,
    'goal', p_side, p_minute, p_is_own_goal, auth.uid()
  )
  returning * into v_event;

  return v_event;
end;
$$;

grant execute on function public.create_team(text, text, text, text, boolean) to authenticated;
grant execute on function public.claim_team(uuid) to authenticated;
grant execute on function public.log_goal(uuid, uuid, smallint, public.team_side, uuid, boolean)
  to authenticated;


-- #####################################################################
-- # 20260821120300_03_views.sql
-- #####################################################################

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


-- #####################################################################
-- # 20260821120400_04_rls.sql
-- #####################################################################

-- =====================================================================
-- Anotar Gol - 04 | Row Level Security
-- =====================================================================
-- Modelo de acceso:
--
--   anonimo (anon)      -> lee equipos con is_public = true. Nada mas.
--   viewer / player     -> lee todo su equipo (aunque sea privado).
--   coach               -> ademas escribe jugadores, partidos y eventos.
--   admin               -> ademas gestiona miembros y ajustes.
--   owner               -> ademas puede borrar el equipo.
--
-- Sin estas politicas, la anon key publicada dentro del APK permitiria a
-- cualquiera vaciar la base. Esto es el requisito de seguridad que el
-- plan original no cubria.
-- =====================================================================

alter table public.profiles      enable row level security;
alter table public.teams         enable row level security;
alter table public.team_members  enable row level security;
alter table public.seasons       enable row level security;
alter table public.players       enable row level security;
alter table public.matches       enable row level security;
alter table public.match_events  enable row level security;
alter table public.match_lineups enable row level security;
alter table public.team_settings enable row level security;

-- Nota: NO se usa "force row level security". Las funciones SECURITY
-- DEFINER (permisos, recalculo del marcador) pertenecen a postgres y
-- deben poder saltarse RLS para funcionar.

-- ---------------------------------------------------------------------
-- Helper: comparto equipo con este usuario?
-- ---------------------------------------------------------------------
create or replace function public.shares_team_with(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.team_members mine
    join public.team_members theirs on theirs.team_id = mine.team_id
    where mine.user_id = auth.uid()
      and theirs.user_id = p_user_id
  );
$$;

grant execute on function public.shares_team_with(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.shares_team_with(id));

drop policy if exists profiles_insert_self on public.profiles;
create policy profiles_insert_self on public.profiles
  for insert to authenticated
  with check (id = auth.uid());

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- ---------------------------------------------------------------------
-- teams
-- ---------------------------------------------------------------------
drop policy if exists teams_select on public.teams;
create policy teams_select on public.teams
  for select to anon, authenticated
  using (is_public or public.is_team_member(id));

drop policy if exists teams_insert on public.teams;
create policy teams_insert on public.teams
  for insert to authenticated
  with check (created_by = auth.uid());

drop policy if exists teams_update on public.teams;
create policy teams_update on public.teams
  for update to authenticated
  using (public.can_admin_team(id))
  with check (public.can_admin_team(id));

drop policy if exists teams_delete on public.teams;
create policy teams_delete on public.teams
  for delete to authenticated
  using (public.team_role_of(id) = 'owner');

-- ---------------------------------------------------------------------
-- team_members
-- ---------------------------------------------------------------------
drop policy if exists team_members_select on public.team_members;
create policy team_members_select on public.team_members
  for select to authenticated
  using (public.is_team_member(team_id));

drop policy if exists team_members_insert on public.team_members;
create policy team_members_insert on public.team_members
  for insert to authenticated
  with check (public.can_admin_team(team_id));

drop policy if exists team_members_update on public.team_members;
create policy team_members_update on public.team_members
  for update to authenticated
  using (public.can_admin_team(team_id))
  with check (public.can_admin_team(team_id));

-- Un admin puede sacar a alguien; cualquiera puede salirse solo.
drop policy if exists team_members_delete on public.team_members;
create policy team_members_delete on public.team_members
  for delete to authenticated
  using (public.can_admin_team(team_id) or user_id = auth.uid());

-- ---------------------------------------------------------------------
-- Datos deportivos: leen los que pueden ver, escribe el cuerpo tecnico
-- ---------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['seasons', 'players', 'matches', 'match_events', 'match_lineups']
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
        with check (public.can_edit_team(team_id))
    $fmt$, t || '_insert', t);

    execute format('drop policy if exists %I on public.%I', t || '_update', t);
    execute format($fmt$
      create policy %I on public.%I
        for update to authenticated
        using (public.can_edit_team(team_id))
        with check (public.can_edit_team(team_id))
    $fmt$, t || '_update', t);

    execute format('drop policy if exists %I on public.%I', t || '_delete', t);
    execute format($fmt$
      create policy %I on public.%I
        for delete to authenticated
        using (public.can_edit_team(team_id))
    $fmt$, t || '_delete', t);
  end loop;
end
$$;

-- ---------------------------------------------------------------------
-- team_settings
-- ---------------------------------------------------------------------
drop policy if exists team_settings_select on public.team_settings;
create policy team_settings_select on public.team_settings
  for select to anon, authenticated
  using (public.can_view_team(team_id));

drop policy if exists team_settings_insert on public.team_settings;
create policy team_settings_insert on public.team_settings
  for insert to authenticated
  with check (public.can_admin_team(team_id));

drop policy if exists team_settings_update on public.team_settings;
create policy team_settings_update on public.team_settings
  for update to authenticated
  using (public.can_admin_team(team_id))
  with check (public.can_admin_team(team_id));


-- #####################################################################
-- # 20260821120500_05_realtime_storage.sql
-- #####################################################################

-- =====================================================================
-- Anotar Gol - 05 | Realtime y Storage
-- =====================================================================
-- Realtime es lo que convierte "Seguimiento en vivo del partido" (el
-- texto que ya esta en el banner de la app) en algo real: el hincha ve
-- el gol en su celular en el momento en que el DT lo anota en el suyo.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Publicacion de cambios en vivo
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise notice 'No existe la publicacion supabase_realtime; se omite Realtime.';
    return;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'matches'
  ) then
    alter publication supabase_realtime add table public.matches;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'match_events'
  ) then
    alter publication supabase_realtime add table public.match_events;
  end if;

  -- La plantilla tambien se sincroniza: si el DT da de alta un jugador
  -- desde su celular, aparece en el resto sin recargar.
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'players'
  ) then
    alter publication supabase_realtime add table public.players;
  end if;
end
$$;

-- Necesario para que los eventos UPDATE/DELETE lleguen con la fila
-- completa y Realtime pueda aplicar RLS sobre ellos.
alter table public.matches      replica identity full;
alter table public.match_events replica identity full;
alter table public.players      replica identity full;

-- ---------------------------------------------------------------------
-- Buckets de imagenes
-- ---------------------------------------------------------------------
-- Convencion de ruta: <team_id>/<archivo>. La primera carpeta identifica
-- al equipo y es lo que usan las politicas para decidir quien escribe.
insert into storage.buckets (id, name, public)
values
  ('team-logos',    'team-logos',    true),
  ('player-photos', 'player-photos', true)
on conflict (id) do nothing;

-- Convierte texto a uuid sin reventar si la carpeta no es un uuid.
create or replace function public.safe_uuid(p_text text)
returns uuid
language plpgsql
immutable
as $$
begin
  return p_text::uuid;
exception
  when others then
    return null;
end;
$$;

grant execute on function public.safe_uuid(text) to anon, authenticated;

-- Las politicas sobre storage.objects a veces requieren permisos extra
-- segun el proyecto. Si fallan, la migracion continua y se avisa para
-- crearlas desde el panel (Storage > Policies).
do $$
begin
  drop policy if exists anotar_gol_media_read   on storage.objects;
  drop policy if exists anotar_gol_media_insert on storage.objects;
  drop policy if exists anotar_gol_media_update on storage.objects;
  drop policy if exists anotar_gol_media_delete on storage.objects;

  create policy anotar_gol_media_read on storage.objects
    for select to anon, authenticated
    using (bucket_id in ('team-logos', 'player-photos'));

  create policy anotar_gol_media_insert on storage.objects
    for insert to authenticated
    with check (
      bucket_id in ('team-logos', 'player-photos')
      and public.can_edit_team(public.safe_uuid((storage.foldername(name))[1]))
    );

  create policy anotar_gol_media_update on storage.objects
    for update to authenticated
    using (
      bucket_id in ('team-logos', 'player-photos')
      and public.can_edit_team(public.safe_uuid((storage.foldername(name))[1]))
    );

  create policy anotar_gol_media_delete on storage.objects
    for delete to authenticated
    using (
      bucket_id in ('team-logos', 'player-photos')
      and public.can_edit_team(public.safe_uuid((storage.foldername(name))[1]))
    );
exception
  when insufficient_privilege then
    raise notice 'Sin permisos para crear politicas de storage. Crealas desde el panel de Supabase.';
end
$$;

