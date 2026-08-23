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
--   20260823120000_06_rivales_y_goleadores.sql
--   20260823130000_07_retos_y_chat.sql
--   20260823140000_08_acuerdo_y_borrado_chat.sql
--   20260823150000_09_fix_permisos_acuerdo.sql
--   20260823160000_10_fix_ultimo_owner.sql
--   20260823170000_11_grupos_e_invitaciones.sql
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


-- #####################################################################
-- # 20260823120000_06_rivales_y_goleadores.sql
-- #####################################################################

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


-- #####################################################################
-- # 20260823130000_07_retos_y_chat.sql
-- #####################################################################

-- =====================================================================
-- Anotar Gol - 07 | Capitanes, retos entre equipos y chat
-- =====================================================================
-- Ver docs/RETOS_Y_CHAT.md para el porque de cada decision.
--
-- Resumen del modelo de acceso que se establece aqui:
--
--   * Los clubes nuevos nacen PRIVADOS. Ser "descubrible" (aparecer en
--     la busqueda para retarte) no es lo mismo que ser publico.
--   * El chat interno del equipo es SIEMPRE solo de miembros, incluso si
--     el club decide ser publico.
--   * El chat del reto es solo de los dos capitanes, y solo mientras el
--     reto sigue abierto.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Privacidad por defecto
-- ---------------------------------------------------------------------
-- Los clubes existentes conservan lo que tengan; cambia el default.
alter table public.teams alter column is_public set default false;

-- Aparecer en la busqueda de equipos para poder ser retado. No expone
-- plantilla, partidos ni chat: solo el nombre y los colores.
alter table public.teams
  add column if not exists is_discoverable boolean not null default true;

comment on column public.teams.is_discoverable is
  'Aparece en la busqueda para recibir retos. No abre los datos del club.';

drop policy if exists teams_select on public.teams;
create policy teams_select on public.teams
  for select to anon, authenticated
  using (is_public or is_discoverable or public.is_team_member(id));

-- ---------------------------------------------------------------------
-- 2. Capitan
-- ---------------------------------------------------------------------
-- No es un rol nuevo: es una marca sobre la membresia. El capitan suele
-- ser ademas jugador, y necesita conservar ese rol.
alter table public.team_members
  add column if not exists is_captain boolean not null default false;

create unique index if not exists team_members_un_capitan_por_equipo
  on public.team_members (team_id) where is_captain;

-- El owner y el admin tambien pueden ejercer de capitan, para que el
-- equipo no quede bloqueado si el capitan desaparece.
create or replace function public.can_captain(p_team_id uuid)
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
      and (tm.is_captain or tm.role in ('owner', 'admin'))
  );
$$;

grant execute on function public.can_captain(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 3. Terminos del partido
-- ---------------------------------------------------------------------
alter table public.matches
  add column if not exists opponent_team_id      uuid references public.teams (id) on delete set null,
  add column if not exists duration_minutes      smallint not null default 90,
  add column if not exists substitutions_allowed smallint not null default 5;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'matches_duracion_chk') then
    alter table public.matches add constraint matches_duracion_chk
      check (duration_minutes between 10 and 130);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'matches_cambios_chk') then
    alter table public.matches add constraint matches_cambios_chk
      check (substitutions_allowed between 0 and 11);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'matches_no_contra_si_mismo') then
    alter table public.matches add constraint matches_no_contra_si_mismo
      check (opponent_team_id is null or opponent_team_id <> team_id);
  end if;
end
$$;

comment on column public.matches.opponent_team_id is
  'El rival cuando tambien usa la app. Le da acceso de lectura al partido.';

-- El equipo contrario tiene que poder ver el partido acordado.
drop policy if exists matches_select on public.matches;
create policy matches_select on public.matches
  for select to anon, authenticated
  using (
    public.can_view_team(team_id)
    or (opponent_team_id is not null and public.is_team_member(opponent_team_id))
  );

-- ---------------------------------------------------------------------
-- 4. Retos
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_type where typname = 'challenge_status') then
    create type public.challenge_status as enum (
      'pending', 'accepted', 'rejected', 'cancelled', 'expired', 'played');
  end if;
end
$$;

create table if not exists public.challenges (
  id                    uuid primary key default gen_random_uuid(),
  from_team_id          uuid not null references public.teams (id) on delete cascade,
  to_team_id            uuid not null references public.teams (id) on delete cascade,
  status                public.challenge_status not null default 'pending',
  message               text check (char_length(message) <= 500),

  -- Lo que se negocia entre capitanes.
  proposed_kickoff_at   timestamptz not null,
  venue                 text,
  duration_minutes      smallint not null default 90
                          check (duration_minutes between 10 and 130),
  substitutions_allowed smallint not null default 5
                          check (substitutions_allowed between 0 and 11),

  match_id              uuid references public.matches (id) on delete set null,
  created_by            uuid references auth.users (id) on delete set null,
  responded_by          uuid references auth.users (id) on delete set null,
  responded_at          timestamptz,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),

  constraint reto_no_contra_si_mismo check (from_team_id <> to_team_id)
);

-- Un solo reto abierto entre el mismo par de equipos, en cada sentido.
create unique index if not exists challenges_uno_pendiente
  on public.challenges (from_team_id, to_team_id) where status = 'pending';

create index if not exists challenges_to_idx   on public.challenges (to_team_id, status);
create index if not exists challenges_from_idx on public.challenges (from_team_id, status);

-- ---------------------------------------------------------------------
-- 5. Choque de horarios
-- ---------------------------------------------------------------------
-- SECURITY DEFINER porque tiene que mirar la agenda de los dos equipos,
-- incluida la del rival, sin abrirle sus datos a nadie: solo devuelve
-- true o false.
create or replace function public.hay_conflicto_horario(
  p_team_id   uuid,
  p_inicio    timestamptz,
  p_duracion  int default 90,
  p_excluir_challenge uuid default null
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    -- Partidos ya agendados
    select 1
    from public.matches m
    where (m.team_id = p_team_id or m.opponent_team_id = p_team_id)
      and m.status in ('scheduled', 'live')
      and tstzrange(m.kickoff_at,
                    m.kickoff_at + make_interval(mins => m.duration_minutes))
          && tstzrange(p_inicio, p_inicio + make_interval(mins => p_duracion))
  )
  or exists (
    -- Retos ya aceptados que todavia no generaron partido
    select 1
    from public.challenges c
    where (c.from_team_id = p_team_id or c.to_team_id = p_team_id)
      and c.status = 'accepted'
      and (p_excluir_challenge is null or c.id <> p_excluir_challenge)
      and tstzrange(c.proposed_kickoff_at,
                    c.proposed_kickoff_at + make_interval(mins => c.duration_minutes))
          && tstzrange(p_inicio, p_inicio + make_interval(mins => p_duracion))
  );
$$;

grant execute on function public.hay_conflicto_horario(uuid, timestamptz, int, uuid)
  to authenticated;

-- ---------------------------------------------------------------------
-- 6. Chats
-- ---------------------------------------------------------------------
-- Chat interno del club. Nunca se abre al rival, ni siquiera con el
-- club marcado como publico: por eso la politica exige ser miembro y no
-- usa can_view_team.
create table if not exists public.team_messages (
  id         uuid primary key default gen_random_uuid(),
  team_id    uuid not null references public.teams (id) on delete cascade,
  match_id   uuid references public.matches (id) on delete set null,
  user_id    uuid not null references auth.users (id) on delete cascade,
  body       text not null check (char_length(btrim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);

create index if not exists team_messages_idx
  on public.team_messages (team_id, created_at desc);

comment on table public.team_messages is
  'Chat interno del equipo. Solo miembros, siempre, aunque el club sea publico.';

-- Chat temporal entre los dos capitanes, para coordinar el partido.
create table if not exists public.challenge_messages (
  id           uuid primary key default gen_random_uuid(),
  challenge_id uuid not null references public.challenges (id) on delete cascade,
  user_id      uuid not null references auth.users (id) on delete cascade,
  body         text not null check (char_length(btrim(body)) between 1 and 2000),
  created_at   timestamptz not null default now()
);

create index if not exists challenge_messages_idx
  on public.challenge_messages (challenge_id, created_at);

-- Solo los dos capitanes, y solo mientras el reto siga abierto. Cuando
-- se rechaza, se cancela o se juega, el chat se cierra.
create or replace function public.puede_chatear_reto(p_challenge_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.challenges c
    where c.id = p_challenge_id
      and c.status in ('pending', 'accepted')
      and (public.can_captain(c.from_team_id) or public.can_captain(c.to_team_id))
  );
$$;

grant execute on function public.puede_chatear_reto(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 7. RLS
-- ---------------------------------------------------------------------
alter table public.challenges         enable row level security;
alter table public.challenge_messages enable row level security;
alter table public.team_messages      enable row level security;

-- Retos: los ven los dos clubes implicados; solo los capitanes actuan.
drop policy if exists challenges_select on public.challenges;
create policy challenges_select on public.challenges
  for select to authenticated
  using (public.is_team_member(from_team_id) or public.is_team_member(to_team_id));

drop policy if exists challenges_insert on public.challenges;
create policy challenges_insert on public.challenges
  for insert to authenticated
  with check (public.can_captain(from_team_id));

drop policy if exists challenges_update on public.challenges;
create policy challenges_update on public.challenges
  for update to authenticated
  using (public.can_captain(from_team_id) or public.can_captain(to_team_id))
  with check (public.can_captain(from_team_id) or public.can_captain(to_team_id));

drop policy if exists challenges_delete on public.challenges;
create policy challenges_delete on public.challenges
  for delete to authenticated
  using (public.can_captain(from_team_id));

-- Chat del reto: los dos capitanes, mientras este abierto.
drop policy if exists challenge_messages_select on public.challenge_messages;
create policy challenge_messages_select on public.challenge_messages
  for select to authenticated
  using (public.puede_chatear_reto(challenge_id));

drop policy if exists challenge_messages_insert on public.challenge_messages;
create policy challenge_messages_insert on public.challenge_messages
  for insert to authenticated
  with check (user_id = auth.uid() and public.puede_chatear_reto(challenge_id));

drop policy if exists challenge_messages_delete on public.challenge_messages;
create policy challenge_messages_delete on public.challenge_messages
  for delete to authenticated
  using (user_id = auth.uid());

-- Chat interno: miembros del club. Nada de can_view_team aqui.
drop policy if exists team_messages_select on public.team_messages;
create policy team_messages_select on public.team_messages
  for select to authenticated
  using (public.is_team_member(team_id));

drop policy if exists team_messages_insert on public.team_messages;
create policy team_messages_insert on public.team_messages
  for insert to authenticated
  with check (user_id = auth.uid() and public.is_team_member(team_id));

drop policy if exists team_messages_delete on public.team_messages;
create policy team_messages_delete on public.team_messages
  for delete to authenticated
  using (user_id = auth.uid() or public.can_admin_team(team_id));

-- ---------------------------------------------------------------------
-- 8. RPC del flujo de reto
-- ---------------------------------------------------------------------

-- Retar a otro equipo.
create or replace function public.retar_equipo(
  p_from_team_id uuid,
  p_to_team_id   uuid,
  p_kickoff      timestamptz,
  p_venue        text default null,
  p_duracion     int  default 90,
  p_cambios      int  default 5,
  p_mensaje      text default null
)
returns public.challenges
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_reto public.challenges;
begin
  if not public.can_captain(p_from_team_id) then
    raise exception 'Solo el capitán puede retar a otro equipo'
      using errcode = '42501';
  end if;

  if p_from_team_id = p_to_team_id then
    raise exception 'Un equipo no puede retarse a sí mismo' using errcode = '23514';
  end if;

  if p_kickoff <= now() then
    raise exception 'La fecha del partido tiene que ser futura' using errcode = '23514';
  end if;

  if public.hay_conflicto_horario(p_from_team_id, p_kickoff, p_duracion) then
    raise exception 'Ya tienes un partido a esa hora' using errcode = '23505';
  end if;

  insert into public.challenges (
    from_team_id, to_team_id, proposed_kickoff_at, venue,
    duration_minutes, substitutions_allowed, message, created_by
  )
  values (
    p_from_team_id, p_to_team_id, p_kickoff, p_venue,
    p_duracion, p_cambios, p_mensaje, auth.uid()
  )
  returning * into v_reto;

  return v_reto;
end;
$$;

-- Ajustar los terminos mientras se negocia. Cualquiera de los dos
-- capitanes, solo con el reto pendiente.
create or replace function public.actualizar_terminos_reto(
  p_challenge_id uuid,
  p_kickoff      timestamptz default null,
  p_venue        text        default null,
  p_duracion     int         default null,
  p_cambios      int         default null
)
returns public.challenges
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_reto public.challenges;
begin
  select * into v_reto from public.challenges where id = p_challenge_id;

  if v_reto.id is null then
    raise exception 'El reto no existe' using errcode = 'P0002';
  end if;

  if v_reto.status <> 'pending' then
    raise exception 'Este reto ya no está en negociación' using errcode = '23514';
  end if;

  if not (public.can_captain(v_reto.from_team_id)
          or public.can_captain(v_reto.to_team_id)) then
    raise exception 'Solo los capitanes pueden cambiar los términos'
      using errcode = '42501';
  end if;

  update public.challenges
  set proposed_kickoff_at   = coalesce(p_kickoff, proposed_kickoff_at),
      venue                 = coalesce(p_venue, venue),
      duration_minutes      = coalesce(p_duracion, duration_minutes),
      substitutions_allowed = coalesce(p_cambios, substitutions_allowed),
      updated_at            = now()
  where id = p_challenge_id
  returning * into v_reto;

  return v_reto;
end;
$$;

-- Aceptar o rechazar. Aceptar crea el partido con los terminos pactados
-- y lo deja visible para los dos clubes.
create or replace function public.responder_reto(
  p_challenge_id uuid,
  p_aceptar      boolean
)
returns public.challenges
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_reto    public.challenges;
  v_rival   text;
  v_match   uuid;
begin
  select * into v_reto from public.challenges where id = p_challenge_id;

  if v_reto.id is null then
    raise exception 'El reto no existe' using errcode = 'P0002';
  end if;

  if v_reto.status <> 'pending' then
    raise exception 'Este reto ya fue respondido' using errcode = '23514';
  end if;

  -- Responde el equipo retado.
  if not public.can_captain(v_reto.to_team_id) then
    raise exception 'Solo el capitán del equipo retado puede responder'
      using errcode = '42501';
  end if;

  if not p_aceptar then
    update public.challenges
    set status = 'rejected', responded_by = auth.uid(), responded_at = now(),
        updated_at = now()
    where id = p_challenge_id
    returning * into v_reto;
    return v_reto;
  end if;

  -- Al aceptar hay que revisar la agenda de los dos, no solo la propia.
  if public.hay_conflicto_horario(
       v_reto.to_team_id, v_reto.proposed_kickoff_at,
       v_reto.duration_minutes, p_challenge_id) then
    raise exception 'Ya tienes un partido a esa hora' using errcode = '23505';
  end if;

  if public.hay_conflicto_horario(
       v_reto.from_team_id, v_reto.proposed_kickoff_at,
       v_reto.duration_minutes, p_challenge_id) then
    raise exception 'El otro equipo ya tiene un partido a esa hora'
      using errcode = '23505';
  end if;

  select name into v_rival from public.teams where id = v_reto.to_team_id;

  -- El partido lo lleva quien reto (es su marcador); el retado queda
  -- como opponent_team_id y por eso puede verlo.
  insert into public.matches (
    team_id, opponent_team_id, opponent_name, kickoff_at, venue,
    duration_minutes, substitutions_allowed, status, is_home, created_by
  )
  values (
    v_reto.from_team_id, v_reto.to_team_id, v_rival,
    v_reto.proposed_kickoff_at, v_reto.venue,
    v_reto.duration_minutes, v_reto.substitutions_allowed,
    'scheduled', true, auth.uid()
  )
  returning id into v_match;

  update public.challenges
  set status = 'accepted', match_id = v_match, responded_by = auth.uid(),
      responded_at = now(), updated_at = now()
  where id = p_challenge_id
  returning * into v_reto;

  return v_reto;
end;
$$;

create or replace function public.cancelar_reto(p_challenge_id uuid)
returns public.challenges
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_reto public.challenges;
begin
  select * into v_reto from public.challenges where id = p_challenge_id;

  if v_reto.id is null then
    raise exception 'El reto no existe' using errcode = 'P0002';
  end if;

  if not (public.can_captain(v_reto.from_team_id)
          or public.can_captain(v_reto.to_team_id)) then
    raise exception 'Solo los capitanes pueden cancelar' using errcode = '42501';
  end if;

  update public.challenges
  set status = 'cancelled', responded_by = auth.uid(), responded_at = now(),
      updated_at = now()
  where id = p_challenge_id
  returning * into v_reto;

  return v_reto;
end;
$$;

grant execute on function public.retar_equipo(uuid, uuid, timestamptz, text, int, int, text) to authenticated;
grant execute on function public.actualizar_terminos_reto(uuid, timestamptz, text, int, int) to authenticated;
grant execute on function public.responder_reto(uuid, boolean) to authenticated;
grant execute on function public.cancelar_reto(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 9. Vista de retos recibidos, con aviso de choque
-- ---------------------------------------------------------------------
drop view if exists public.retos_recibidos;
create view public.retos_recibidos
with (security_invoker = true)
as
select
  c.id,
  c.from_team_id,
  c.to_team_id,
  t.name        as equipo_retador,
  t.logo_url    as logo_retador,
  c.status,
  c.message,
  c.proposed_kickoff_at,
  c.venue,
  c.duration_minutes,
  c.substitutions_allowed,
  c.match_id,
  c.created_at,
  -- Aviso, no bloqueo: el capitan decide, pero informado.
  public.hay_conflicto_horario(
    c.to_team_id, c.proposed_kickoff_at, c.duration_minutes, c.id) as choca_con_tu_agenda
from public.challenges c
join public.teams t on t.id = c.from_team_id;

grant select on public.retos_recibidos to authenticated;

-- ---------------------------------------------------------------------
-- 10. Tiempo real y updated_at
-- ---------------------------------------------------------------------
-- El chat va por WebSocket, no por sondeo: es lo que lo hace inmediato.
do $$
declare
  t text;
begin
  execute 'drop trigger if exists set_updated_at on public.challenges';
  execute 'create trigger set_updated_at before update on public.challenges
           for each row execute function public.set_updated_at()';

  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['team_messages', 'challenge_messages', 'challenges']
    loop
      if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public' and tablename = t
      ) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    end loop;
  end if;
end
$$;

alter table public.team_messages      replica identity full;
alter table public.challenge_messages replica identity full;
alter table public.challenges         replica identity full;


-- #####################################################################
-- # 20260823140000_08_acuerdo_y_borrado_chat.sql
-- #####################################################################

-- =====================================================================
-- Anotar Gol - 08 | "Quedaron de acuerdo" y borrado del chat temporal
-- =====================================================================
-- Ajuste del flujo pedido el 23/08/2026:
--
--   El chat entre capitanes es temporal y existe solo para coordinar.
--   Cuando pulsan "Quedaron de acuerdo", se avisa que el chat se va a
--   borrar; si confirman, se borra, se registra el partido acordado y
--   RECIEN AHI aparece en el cronograma.
--
-- El borrado no es cosmetico: el chat de coordinacion no tiene por que
-- quedarse ocupando espacio para siempre.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. El chat muere con el reto
-- ---------------------------------------------------------------------
-- Cubre todas las salidas: acordado, rechazado, cancelado o vencido.
-- Ponerlo en un trigger y no en cada RPC evita que un camino nuevo se
-- olvide de limpiar.
create or replace function public.borrar_chat_del_reto()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.status <> 'pending' and old.status = 'pending' then
    delete from public.challenge_messages where challenge_id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists challenges_borrar_chat on public.challenges;
create trigger challenges_borrar_chat
  after update on public.challenges
  for each row execute function public.borrar_chat_del_reto();

comment on function public.borrar_chat_del_reto is
  'Borra el chat temporal en cuanto el reto deja de estar en negociación.';

-- ---------------------------------------------------------------------
-- 2. Confirmar el acuerdo
-- ---------------------------------------------------------------------
-- Es el boton "Quedaron de acuerdo". Puede pulsarlo cualquiera de los
-- dos capitanes: para ese punto ya lo hablaron en el chat, y exigir dos
-- confirmaciones agregaria un paso que nadie pidio.
--
-- Devuelve el reto ya cerrado, con match_id apuntando al partido nuevo.
create or replace function public.confirmar_acuerdo(p_challenge_id uuid)
returns public.challenges
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_reto  public.challenges;
  v_rival text;
  v_match uuid;
begin
  select * into v_reto from public.challenges where id = p_challenge_id;

  if v_reto.id is null then
    raise exception 'El reto no existe' using errcode = 'P0002';
  end if;

  if v_reto.status <> 'pending' then
    raise exception 'Este reto ya se cerró' using errcode = '23514';
  end if;

  if not (public.can_captain(v_reto.from_team_id)
          or public.can_captain(v_reto.to_team_id)) then
    raise exception 'Solo los capitanes pueden confirmar el acuerdo'
      using errcode = '42501';
  end if;

  if v_reto.proposed_kickoff_at <= now() then
    raise exception 'La fecha acordada ya pasó. Ajusten el horario primero.'
      using errcode = '23514';
  end if;

  -- Se revisa la agenda de los dos, no solo la de quien pulsa.
  if public.hay_conflicto_horario(
       v_reto.from_team_id, v_reto.proposed_kickoff_at,
       v_reto.duration_minutes, p_challenge_id) then
    raise exception 'El equipo retador ya tiene un partido a esa hora'
      using errcode = '23505';
  end if;

  if public.hay_conflicto_horario(
       v_reto.to_team_id, v_reto.proposed_kickoff_at,
       v_reto.duration_minutes, p_challenge_id) then
    raise exception 'El equipo retado ya tiene un partido a esa hora'
      using errcode = '23505';
  end if;

  select name into v_rival from public.teams where id = v_reto.to_team_id;

  -- El partido lo lleva quien reto (es su marcador). El retado queda
  -- como opponent_team_id, que es lo que le da acceso de lectura.
  insert into public.matches (
    team_id, opponent_team_id, opponent_name, kickoff_at, venue,
    duration_minutes, substitutions_allowed, status, is_home, created_by
  )
  values (
    v_reto.from_team_id, v_reto.to_team_id, v_rival,
    v_reto.proposed_kickoff_at, v_reto.venue,
    v_reto.duration_minutes, v_reto.substitutions_allowed,
    'scheduled', true, auth.uid()
  )
  returning id into v_match;

  -- Al salir de 'pending', el trigger de arriba borra el chat.
  update public.challenges
  set status       = 'accepted',
      match_id     = v_match,
      responded_by = auth.uid(),
      responded_at = now(),
      updated_at   = now()
  where id = p_challenge_id
  returning * into v_reto;

  return v_reto;
end;
$$;

grant execute on function public.confirmar_acuerdo(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 3. El cronograma
-- ---------------------------------------------------------------------
-- Solo partidos ya acordados. Un reto en negociacion NO aparece aca:
-- entra al cronograma recien cuando los capitanes confirman.
drop view if exists public.cronograma;
create view public.cronograma
with (security_invoker = true)
as
select
  m.id,
  m.team_id,
  m.opponent_team_id,
  m.opponent_name,
  m.kickoff_at,
  m.kickoff_at + make_interval(mins => m.duration_minutes) as termina_at,
  m.venue,
  m.competition,
  m.status,
  m.is_home,
  m.duration_minutes,
  m.substitutions_allowed,
  m.team_score,
  m.opponent_score,
  local.name  as club_local,
  visita.name as club_visitante,
  -- true si el rival tambien usa la app (partido acordado por reto).
  (m.opponent_team_id is not null) as rival_en_la_app
from public.matches m
join public.teams local on local.id = m.team_id
left join public.teams visita on visita.id = m.opponent_team_id
where m.status in ('scheduled', 'live');

comment on view public.cronograma is
  'Partidos agendados. Un reto entra aquí solo cuando los capitanes confirman.';

grant select on public.cronograma to anon, authenticated;

-- ---------------------------------------------------------------------
-- 4. Vencimiento de retos viejos
-- ---------------------------------------------------------------------
-- Un reto cuya fecha ya paso sin respuesta no deberia seguir abierto ni
-- conservando su chat. Se llama desde la app al abrir la bandeja.
create or replace function public.vencer_retos_pasados()
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_afectados int;
begin
  update public.challenges
  set status = 'expired', updated_at = now()
  where status = 'pending'
    and proposed_kickoff_at < now();

  get diagnostics v_afectados = row_count;
  return v_afectados;
end;
$$;

grant execute on function public.vencer_retos_pasados() to authenticated;


-- #####################################################################
-- # 20260823150000_09_fix_permisos_acuerdo.sql
-- #####################################################################

-- =====================================================================
-- Anotar Gol - 09 | Corrección: quien crea el partido acordado
-- =====================================================================
-- Bug encontrado al probar el flujo completo contra la base real.
--
-- Sintoma:
--   El capitán del equipo RETADO pulsa "Quedaron de acuerdo" y falla con
--   "new row violates row-level security policy for table matches".
--
-- Causa:
--   El partido se crea a nombre del equipo RETADOR (es su marcador),
--   pero `confirmar_acuerdo` corria con los permisos de quien la llama.
--   La politica de insercion de `matches` exige `can_edit_team(team_id)`,
--   y el capitán retado no es miembro del club retador. RLS hacia bien
--   su trabajo; la funcion estaba mal planteada.
--
-- Arreglo:
--   Las dos funciones que cierran un reto pasan a SECURITY DEFINER. La
--   autorizacion no desaparece: la hace la propia funcion, que exige ser
--   capitán de uno de los dos equipos y solo puede crear un partido
--   entre esos dos. Es el patron correcto para una operacion que cruza
--   la frontera de dos clubes.
--
-- Alternativa descartada: aflojar la politica de `matches` para permitir
-- insertar en nombre de otro club. Eso abriria un agujero para todo el
-- mundo, no solo para este flujo.
-- =====================================================================

create or replace function public.confirmar_acuerdo(p_challenge_id uuid)
returns public.challenges
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_reto  public.challenges;
  v_rival text;
  v_match uuid;
begin
  select * into v_reto from public.challenges where id = p_challenge_id;

  if v_reto.id is null then
    raise exception 'El reto no existe' using errcode = 'P0002';
  end if;

  if v_reto.status <> 'pending' then
    raise exception 'Este reto ya se cerró' using errcode = '23514';
  end if;

  -- La autorizacion vive aqui, no en RLS: sin esto, SECURITY DEFINER
  -- dejaria que cualquiera cerrara retos ajenos.
  if not (public.can_captain(v_reto.from_team_id)
          or public.can_captain(v_reto.to_team_id)) then
    raise exception 'Solo los capitanes pueden confirmar el acuerdo'
      using errcode = '42501';
  end if;

  if v_reto.proposed_kickoff_at <= now() then
    raise exception 'La fecha acordada ya pasó. Ajusten el horario primero.'
      using errcode = '23514';
  end if;

  if public.hay_conflicto_horario(
       v_reto.from_team_id, v_reto.proposed_kickoff_at,
       v_reto.duration_minutes, p_challenge_id) then
    raise exception 'El equipo retador ya tiene un partido a esa hora'
      using errcode = '23505';
  end if;

  if public.hay_conflicto_horario(
       v_reto.to_team_id, v_reto.proposed_kickoff_at,
       v_reto.duration_minutes, p_challenge_id) then
    raise exception 'El equipo retado ya tiene un partido a esa hora'
      using errcode = '23505';
  end if;

  select name into v_rival from public.teams where id = v_reto.to_team_id;

  insert into public.matches (
    team_id, opponent_team_id, opponent_name, kickoff_at, venue,
    duration_minutes, substitutions_allowed, status, is_home, created_by
  )
  values (
    v_reto.from_team_id, v_reto.to_team_id, v_rival,
    v_reto.proposed_kickoff_at, v_reto.venue,
    v_reto.duration_minutes, v_reto.substitutions_allowed,
    'scheduled', true, auth.uid()
  )
  returning id into v_match;

  -- Al salir de 'pending', el trigger borra el chat temporal.
  update public.challenges
  set status       = 'accepted',
      match_id     = v_match,
      responded_by = auth.uid(),
      responded_at = now(),
      updated_at   = now()
  where id = p_challenge_id
  returning * into v_reto;

  return v_reto;
end;
$$;

-- Mismo problema en responder_reto cuando se acepta.
create or replace function public.responder_reto(
  p_challenge_id uuid,
  p_aceptar      boolean
)
returns public.challenges
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_reto public.challenges;
begin
  select * into v_reto from public.challenges where id = p_challenge_id;

  if v_reto.id is null then
    raise exception 'El reto no existe' using errcode = 'P0002';
  end if;

  if v_reto.status <> 'pending' then
    raise exception 'Este reto ya fue respondido' using errcode = '23514';
  end if;

  -- Rechazar es potestad del equipo retado.
  if not public.can_captain(v_reto.to_team_id) then
    raise exception 'Solo el capitán del equipo retado puede responder'
      using errcode = '42501';
  end if;

  if p_aceptar then
    -- Aceptar es exactamente "quedaron de acuerdo": un solo camino, para
    -- que el chat se borre y el partido se registre siempre igual.
    return public.confirmar_acuerdo(p_challenge_id);
  end if;

  update public.challenges
  set status = 'rejected', responded_by = auth.uid(), responded_at = now(),
      updated_at = now()
  where id = p_challenge_id
  returning * into v_reto;

  return v_reto;
end;
$$;

grant execute on function public.confirmar_acuerdo(uuid) to authenticated;
grant execute on function public.responder_reto(uuid, boolean) to authenticated;


-- #####################################################################
-- # 20260823160000_10_fix_ultimo_owner.sql
-- #####################################################################

-- =====================================================================
-- Anotar Gol - 10 | Corrección: el guardián del último owner era muy duro
-- =====================================================================
-- Bug encontrado al limpiar datos de prueba.
--
-- Sintoma:
--   Borrar la cuenta de una persona que es el unico `owner` de un club
--   falla con "El equipo debe conservar al menos un owner".
--
-- Por que importa:
--   No es solo un problema de pruebas. Google Play y la App Store exigen
--   que una app con cuentas permita BORRAR la cuenta desde dentro. Con
--   este trigger tal como estaba, el fundador de un club nunca podria
--   darse de baja.
--
-- Arreglo:
--   La proteccion sigue en pie para el caso que importa (que a alguien
--   le quiten el ultimo owner por error), pero se levanta cuando la fila
--   desaparece por arrastre: porque se borro el equipo, o porque se
--   borro el usuario.
-- =====================================================================

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

  if tg_op = 'UPDATE' and new.role = 'owner' then
    return new;
  end if;

  -- Si el equipo entero se esta borrando (cascade), no hay nada que proteger.
  if not exists (select 1 from public.teams where id = v_team_id) then
    return coalesce(new, old);
  end if;

  -- Si la persona ya no existe, la fila cae por arrastre de auth.users.
  -- Bloquearlo aqui impediria borrar la cuenta, que es un requisito de
  -- las dos tiendas.
  if tg_op = 'DELETE'
     and not exists (select 1 from auth.users where id = old.user_id) then
    return old;
  end if;

  select count(*) into v_owners
  from public.team_members
  where team_id = v_team_id and role = 'owner';

  if v_owners <= 1 then
    raise exception 'El equipo debe conservar al menos un owner'
      using errcode = '23514',
            hint = 'Nombra otro owner antes de quitar a este.';
  end if;

  return coalesce(new, old);
end;
$$;

comment on function public.protect_last_owner is
  'Impide quitar al último owner por error, pero no bloquea el borrado de la cuenta.';


-- #####################################################################
-- # 20260823170000_11_grupos_e_invitaciones.sql
-- #####################################################################

-- =====================================================================
-- Anotar Gol - 11 | Grupos, invitaciones y aislamiento entre ligas
-- =====================================================================
-- Requisito del 23/08/2026:
--
--   Existen GRUPOS (ligas, torneos, barrios) y dentro de cada uno hay
--   equipos. El grupo A y el grupo B no saben nada el uno del otro. Si
--   eres del grupo A, solo ves informacion del grupo A. Por eso entrar
--   a un grupo requiere una CLAVE DE INVITACION.
--
--   Una persona puede estar en varios grupos, con equipos distintos. Los
--   choques de horario ENTRE grupos son problema suyo; los choques
--   DENTRO de un mismo grupo no pueden pasar.
--
-- Esto convierte al grupo en la frontera de privacidad principal. Antes
-- la frontera era el equipo; ahora el equipo vive dentro de un grupo.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Grupos
-- ---------------------------------------------------------------------
create table if not exists public.groups (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(btrim(name)) between 2 and 80),
  slug        text unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  description text,
  created_by  uuid references auth.users (id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table public.groups is
  'Liga, torneo o comunidad. Frontera de privacidad: un grupo no ve a otro.';

do $$
begin
  if not exists (select 1 from pg_type where typname = 'group_role') then
    create type public.group_role as enum ('group_admin', 'member');
  end if;
end
$$;

create table if not exists public.group_members (
  group_id  uuid not null references public.groups (id) on delete cascade,
  user_id   uuid not null references auth.users (id) on delete cascade,
  role      public.group_role not null default 'member',
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create index if not exists group_members_user_idx on public.group_members (user_id);

-- Los equipos viven dentro de un grupo. Nullable a proposito: el club
-- de ejemplo del seed no pertenece a ninguno y sigue funcionando suelto.
alter table public.teams
  add column if not exists group_id uuid references public.groups (id) on delete cascade;

create index if not exists teams_group_idx on public.teams (group_id);

-- ---------------------------------------------------------------------
-- 2. Invitaciones
-- ---------------------------------------------------------------------
create table if not exists public.group_invites (
  id         uuid primary key default gen_random_uuid(),
  group_id   uuid not null references public.groups (id) on delete cascade,
  code       text not null unique,
  created_by uuid references auth.users (id) on delete set null,
  max_uses   int,                      -- null = sin limite
  uses       int not null default 0,
  expires_at timestamptz,              -- null = sin vencimiento
  is_active  boolean not null default true,
  created_at timestamptz not null default now()
);

create index if not exists group_invites_group_idx on public.group_invites (group_id);

-- Codigo corto y legible en voz alta. Sin O/0 ni I/1 para que nadie lo
-- dicte mal por WhatsApp.
create or replace function public.generar_codigo_invitacion()
returns text
language plpgsql
volatile
as $$
declare
  v_alfabeto text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_codigo   text;
  v_intento  int := 0;
begin
  loop
    v_codigo := '';
    for i in 1..8 loop
      v_codigo := v_codigo ||
        substr(v_alfabeto, 1 + floor(random() * length(v_alfabeto))::int, 1);
    end loop;

    exit when not exists (select 1 from public.group_invites gi where gi.code = v_codigo);

    v_intento := v_intento + 1;
    if v_intento > 50 then
      raise exception 'No se pudo generar un código libre';
    end if;
  end loop;

  return v_codigo;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. Pertenencia y visibilidad
-- ---------------------------------------------------------------------
create or replace function public.es_miembro_del_grupo(p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.group_members gm
    where gm.group_id = p_group_id and gm.user_id = auth.uid()
  );
$$;

create or replace function public.es_admin_del_grupo(p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.group_members gm
    where gm.group_id = p_group_id
      and gm.user_id = auth.uid()
      and gm.role = 'group_admin'
  );
$$;

-- Compartimos grupo con este equipo?
create or replace function public.comparte_grupo_con_equipo(p_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.teams t
    join public.group_members gm on gm.group_id = t.group_id
    where t.id = p_team_id and gm.user_id = auth.uid()
  );
$$;

grant execute on function public.es_miembro_del_grupo(uuid)      to authenticated;
grant execute on function public.es_admin_del_grupo(uuid)        to authenticated;
grant execute on function public.comparte_grupo_con_equipo(uuid) to authenticated;

-- Regla de lectura actualizada. El orden importa para entenderla:
--   1. Soy del equipo            -> veo todo.
--   2. El equipo esta en un grupo -> lo veo solo si soy de ese grupo.
--   3. El equipo NO esta en grupo -> vale el is_public de siempre
--      (asi el club de ejemplo sigue abierto para demos).
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
      and (
        public.is_team_member(t.id)
        or (t.group_id is not null and public.es_miembro_del_grupo(t.group_id))
        or (t.group_id is null and t.is_public)
      )
  );
$$;

-- Buscar equipos para retar: solo dentro de tus grupos.
drop policy if exists teams_select on public.teams;
create policy teams_select on public.teams
  for select to anon, authenticated
  using (
    public.is_team_member(id)
    or (group_id is not null
        and is_discoverable
        and public.es_miembro_del_grupo(group_id))
    or (group_id is null and is_public)
  );

-- ---------------------------------------------------------------------
-- 4. RLS de grupos
-- ---------------------------------------------------------------------
alter table public.groups        enable row level security;
alter table public.group_members enable row level security;
alter table public.group_invites enable row level security;

drop policy if exists groups_select on public.groups;
create policy groups_select on public.groups
  for select to authenticated
  using (public.es_miembro_del_grupo(id));

drop policy if exists groups_update on public.groups;
create policy groups_update on public.groups
  for update to authenticated
  using (public.es_admin_del_grupo(id))
  with check (public.es_admin_del_grupo(id));

drop policy if exists groups_delete on public.groups;
create policy groups_delete on public.groups
  for delete to authenticated
  using (public.es_admin_del_grupo(id));

-- Ves a los miembros de tus grupos, no a los de otros.
drop policy if exists group_members_select on public.group_members;
create policy group_members_select on public.group_members
  for select to authenticated
  using (public.es_miembro_del_grupo(group_id));

drop policy if exists group_members_update on public.group_members;
create policy group_members_update on public.group_members
  for update to authenticated
  using (public.es_admin_del_grupo(group_id))
  with check (public.es_admin_del_grupo(group_id));

-- Un admin echa a alguien; cualquiera puede salirse solo.
drop policy if exists group_members_delete on public.group_members;
create policy group_members_delete on public.group_members
  for delete to authenticated
  using (public.es_admin_del_grupo(group_id) or user_id = auth.uid());

-- Los codigos los ve y los crea el admin del grupo. Canjearlos se hace
-- por RPC, no leyendo esta tabla: si no, cualquiera del grupo podria
-- repartir invitaciones ajenas.
drop policy if exists group_invites_select on public.group_invites;
create policy group_invites_select on public.group_invites
  for select to authenticated
  using (public.es_admin_del_grupo(group_id));

drop policy if exists group_invites_insert on public.group_invites;
create policy group_invites_insert on public.group_invites
  for insert to authenticated
  with check (public.es_admin_del_grupo(group_id));

drop policy if exists group_invites_update on public.group_invites;
create policy group_invites_update on public.group_invites
  for update to authenticated
  using (public.es_admin_del_grupo(group_id))
  with check (public.es_admin_del_grupo(group_id));

drop policy if exists group_invites_delete on public.group_invites;
create policy group_invites_delete on public.group_invites
  for delete to authenticated
  using (public.es_admin_del_grupo(group_id));

-- ---------------------------------------------------------------------
-- 5. RPC de grupos
-- ---------------------------------------------------------------------
create or replace function public.crear_grupo(
  p_nombre      text,
  p_descripcion text default null
)
returns public.groups
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_grupo public.groups;
  v_base  text;
  v_slug  text;
  v_n     int := 0;
begin
  if auth.uid() is null then
    raise exception 'Debes iniciar sesión' using errcode = '42501';
  end if;

  v_base := coalesce(nullif(public.slugify(p_nombre), ''), 'grupo');
  v_slug := v_base;
  while exists (select 1 from public.groups g where g.slug = v_slug) loop
    v_n := v_n + 1;
    v_slug := v_base || '-' || v_n;
  end loop;

  insert into public.groups (name, slug, description, created_by)
  values (btrim(p_nombre), v_slug, p_descripcion, auth.uid())
  returning * into v_grupo;

  insert into public.group_members (group_id, user_id, role)
  values (v_grupo.id, auth.uid(), 'group_admin');

  -- Un grupo sin invitacion no sirve de nada: se crea una de una vez.
  insert into public.group_invites (group_id, code, created_by)
  values (v_grupo.id, public.generar_codigo_invitacion(), auth.uid());

  return v_grupo;
end;
$$;

create or replace function public.crear_invitacion(
  p_group_id  uuid,
  p_max_usos  int default null,
  p_dias      int default null
)
returns public.group_invites
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_inv public.group_invites;
begin
  if not public.es_admin_del_grupo(p_group_id) then
    raise exception 'Solo un administrador del grupo puede crear invitaciones'
      using errcode = '42501';
  end if;

  insert into public.group_invites (group_id, code, created_by, max_uses, expires_at)
  values (
    p_group_id,
    public.generar_codigo_invitacion(),
    auth.uid(),
    p_max_usos,
    case when p_dias is null then null else now() + make_interval(days => p_dias) end
  )
  returning * into v_inv;

  return v_inv;
end;
$$;

-- Canjear el codigo. Es la puerta de entrada: sin esto, una cuenta nueva
-- no pertenece a ningun grupo y no ve absolutamente nada.
create or replace function public.unirse_con_codigo(p_codigo text)
returns public.groups
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_inv   public.group_invites;
  v_grupo public.groups;
begin
  if auth.uid() is null then
    raise exception 'Debes iniciar sesión' using errcode = '42501';
  end if;

  select * into v_inv
  from public.group_invites
  where upper(btrim(code)) = upper(btrim(p_codigo));

  if v_inv.id is null then
    raise exception 'Esa clave de invitación no existe' using errcode = 'P0002';
  end if;

  if not v_inv.is_active then
    raise exception 'Esa invitación fue desactivada' using errcode = '42501';
  end if;

  if v_inv.expires_at is not null and v_inv.expires_at < now() then
    raise exception 'Esa invitación ya venció' using errcode = '42501';
  end if;

  if v_inv.max_uses is not null and v_inv.uses >= v_inv.max_uses then
    raise exception 'Esa invitación ya se usó el máximo de veces'
      using errcode = '42501';
  end if;

  select * into v_grupo from public.groups where id = v_inv.group_id;

  -- Volver a canjear el mismo codigo no gasta un uso ni duplica nada.
  if exists (
    select 1 from public.group_members
    where group_id = v_inv.group_id and user_id = auth.uid()
  ) then
    return v_grupo;
  end if;

  insert into public.group_members (group_id, user_id, role)
  values (v_inv.group_id, auth.uid(), 'member');

  update public.group_invites set uses = uses + 1 where id = v_inv.id;

  return v_grupo;
end;
$$;

-- Los grupos a los que perteneces, para el selector del perfil.
create or replace function public.mis_grupos()
returns table (
  id          uuid,
  name        text,
  slug        text,
  description text,
  rol         public.group_role,
  equipos     bigint,
  joined_at   timestamptz
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select g.id, g.name, g.slug, g.description, gm.role,
         (select count(*) from public.teams t where t.group_id = g.id),
         gm.joined_at
  from public.group_members gm
  join public.groups g on g.id = gm.group_id
  where gm.user_id = auth.uid()
  order by gm.joined_at;
$$;

grant execute on function public.crear_grupo(text, text)          to authenticated;
grant execute on function public.crear_invitacion(uuid, int, int) to authenticated;
grant execute on function public.unirse_con_codigo(text)          to authenticated;
grant execute on function public.mis_grupos()                     to authenticated;

-- ---------------------------------------------------------------------
-- 6. Los retos no cruzan grupos
-- ---------------------------------------------------------------------
create or replace function public.retar_equipo(
  p_from_team_id uuid,
  p_to_team_id   uuid,
  p_kickoff      timestamptz,
  p_venue        text default null,
  p_duracion     int  default 90,
  p_cambios      int  default 5,
  p_mensaje      text default null
)
returns public.challenges
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_reto     public.challenges;
  v_grupo_a  uuid;
  v_grupo_b  uuid;
begin
  if not public.can_captain(p_from_team_id) then
    raise exception 'Solo el capitán puede retar a otro equipo'
      using errcode = '42501';
  end if;

  if p_from_team_id = p_to_team_id then
    raise exception 'Un equipo no puede retarse a sí mismo' using errcode = '23514';
  end if;

  select group_id into v_grupo_a from public.teams where id = p_from_team_id;
  select group_id into v_grupo_b from public.teams where id = p_to_team_id;

  -- Un grupo no ve al otro: tampoco puede retarlo.
  if v_grupo_a is distinct from v_grupo_b then
    raise exception 'Solo puedes retar a equipos de tu mismo grupo'
      using errcode = '42501';
  end if;

  if p_kickoff <= now() then
    raise exception 'La fecha del partido tiene que ser futura' using errcode = '23514';
  end if;

  if public.hay_conflicto_horario(p_from_team_id, p_kickoff, p_duracion) then
    raise exception 'Ya tienes un partido a esa hora' using errcode = '23505';
  end if;

  insert into public.challenges (
    from_team_id, to_team_id, proposed_kickoff_at, venue,
    duration_minutes, substitutions_allowed, message, created_by
  )
  values (
    p_from_team_id, p_to_team_id, p_kickoff, p_venue,
    p_duracion, p_cambios, p_mensaje, auth.uid()
  )
  returning * into v_reto;

  return v_reto;
end;
$$;

grant execute on function public.retar_equipo(uuid, uuid, timestamptz, text, int, int, text)
  to authenticated;

-- ---------------------------------------------------------------------
-- 7. Choques del jugador, grupo por grupo
-- ---------------------------------------------------------------------
-- Regla pedida: dentro de un mismo grupo, un jugador NUNCA puede tener
-- dos partidos encimados. Entre grupos distintos si puede, y es asunto
-- suyo resolverlo.
create or replace function public.conflictos_del_jugador(p_user_id uuid default null)
returns table (
  group_id        uuid,
  grupo           text,
  match_a         uuid,
  match_b         uuid,
  inicio_a        timestamptz,
  inicio_b        timestamptz,
  equipo_a        text,
  equipo_b        text,
  mismo_grupo     boolean
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with agenda as (
    select m.id, m.kickoff_at,
           m.kickoff_at + make_interval(mins => m.duration_minutes) as fin,
           t.id as team_id, t.name as equipo, t.group_id
    from public.team_members tm
    join public.teams t on t.id = tm.team_id
    join public.matches m
      on (m.team_id = t.id or m.opponent_team_id = t.id)
    where tm.user_id = coalesce(p_user_id, auth.uid())
      and m.status in ('scheduled', 'live')
  )
  select
    a.group_id,
    g.name,
    a.id, b.id,
    a.kickoff_at, b.kickoff_at,
    a.equipo, b.equipo,
    (a.group_id is not distinct from b.group_id)
  from agenda a
  join agenda b
    on a.id < b.id
   and tstzrange(a.kickoff_at, a.fin) && tstzrange(b.kickoff_at, b.fin)
  left join public.groups g on g.id = a.group_id;
$$;

grant execute on function public.conflictos_del_jugador(uuid) to authenticated;

comment on function public.conflictos_del_jugador is
  'Partidos encimados del jugador. mismo_grupo = true es un error a corregir; false es aviso.';

-- ---------------------------------------------------------------------
-- 8. updated_at
-- ---------------------------------------------------------------------
drop trigger if exists set_updated_at on public.groups;
create trigger set_updated_at before update on public.groups
  for each row execute function public.set_updated_at();

