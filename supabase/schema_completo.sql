-- Anotar Gol - esquema completo (GENERADO). No editar: editar las migraciones.
-- Orden:
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
--   20260823180000_12_equipos_dentro_del_grupo.sql
--   20260823190000_13_cuenta_dev.sql
--   20260823200000_14_panel_dev_solo_dev.sql
--   20260823210000_15_el_capitan_crea_su_equipo.sql
--   20260823220000_16_claves_de_capitan.sql
--   20260823230000_17_solicitar_fundar_equipo.sql
--   20260824000000_18_clave_de_equipo.sql
--   20260824010000_19_fix_solicitudes_y_perfiles.sql
--   20260824020000_20_cedulas_y_plantilla_obligatoria.sql
--   20260824030000_21_cedula_es_la_identidad.sql
--   20260824040000_22_reclamar_ficha_y_un_equipo_por_grupo.sql
--   20260824050000_23_fix_casts_al_vincular.sql
--   20260824060000_24_avisos_solo_al_crear.sql
--   20260824070000_25_un_equipo_por_grupo_solo_jugadores.sql
--   20260824080000_26_el_dev_es_invisible.sql
--   20260824090000_27_dev_sin_rastro.sql
--   20260824100000_28_el_dev_es_un_dios.sql
--   20260824110000_29_reloj_del_partido.sql
--   20260824120000_30_revisar_clave.sql
--   20260824130000_31_borrar_cuenta_con_ficha.sql
--   20260824140000_32_sin_hinchas.sql

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


-- #####################################################################
-- # 20260823180000_12_equipos_dentro_del_grupo.sql
-- #####################################################################

-- =====================================================================
-- Anotar Gol - 12 | Los equipos se crean DENTRO de un grupo
-- =====================================================================
-- Un grupo tiene varios equipos y esos equipos se enfrentan entre si.
-- Al probarlo aparecieron dos problemas:
--
-- 1. HUECO FUNCIONAL
--    `create_team` no asignaba grupo, asi que todo equipo creado desde
--    la app nacia fuera de cualquier liga. En las pruebas hubo que
--    asignarlo a mano como postgres, que era la señal de que faltaba.
--
-- 2. AGUJERO DE SEGURIDAD
--    La politica de insercion de `teams` solo exigia
--    `created_by = auth.uid()`. Con eso, cualquiera podia meter un
--    equipo dentro de un grupo ajeno: bastaba con saber su id. Y una vez
--    dentro, su capitan podia retar a los equipos de esa liga privada.
--    Rompia justo la garantia de aislamiento del grupo.
--
-- Se arreglan los dos aqui.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. No se mete un equipo en un grupo del que no eres parte
-- ---------------------------------------------------------------------
drop policy if exists teams_insert on public.teams;
create policy teams_insert on public.teams
  for insert to authenticated
  with check (
    created_by = auth.uid()
    and (group_id is null or public.es_miembro_del_grupo(group_id))
  );

-- Lo mismo al editar: nadie mueve su equipo a una liga ajena.
drop policy if exists teams_update on public.teams;
create policy teams_update on public.teams
  for update to authenticated
  using (public.can_admin_team(id))
  with check (
    public.can_admin_team(id)
    and (group_id is null or public.es_miembro_del_grupo(group_id))
  );

-- ---------------------------------------------------------------------
-- 2. create_team acepta el grupo
-- ---------------------------------------------------------------------
create or replace function public.create_team(
  p_name            text,
  p_short_name      text default null,
  p_primary_color   text default '#1B5E20',
  p_secondary_color text default '#FFD700',
  p_is_public       boolean default false,
  p_group_id        uuid default null
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
    raise exception 'Debes iniciar sesión para crear un equipo'
      using errcode = '42501';
  end if;

  -- La funcion es SECURITY DEFINER, asi que la comprobacion tiene que
  -- estar aqui: RLS no la va a hacer por nosotros.
  if p_group_id is not null and not public.es_miembro_del_grupo(p_group_id) then
    raise exception 'No perteneces a ese grupo'
      using errcode = '42501',
            hint = 'Únete al grupo con su clave de invitación antes de crear el equipo.';
  end if;

  v_base_slug := coalesce(nullif(public.slugify(p_name), ''), 'equipo');
  v_slug := v_base_slug;

  while exists (select 1 from public.teams t where t.slug = v_slug) loop
    v_suffix := v_suffix + 1;
    v_slug := v_base_slug || '-' || v_suffix;
  end loop;

  insert into public.teams (
    name, short_name, slug, primary_color, secondary_color,
    is_public, group_id, created_by
  )
  values (
    btrim(p_name), nullif(btrim(coalesce(p_short_name, '')), ''), v_slug,
    p_primary_color, p_secondary_color, p_is_public, p_group_id, auth.uid()
  )
  returning * into v_team;

  return v_team;
end;
$$;

grant execute on function public.create_team(text, text, text, text, boolean, uuid)
  to authenticated;

-- La firma vieja de 5 argumentos queda para no romper llamadas
-- existentes; crea el equipo sin grupo, como antes.
drop function if exists public.create_team(text, text, text, text, boolean);

-- ---------------------------------------------------------------------
-- 3. Los equipos de un grupo, para elegir a quien retar
-- ---------------------------------------------------------------------
-- Solo equipos del grupo, sin el propio, y con aviso de si el horario
-- que estas pensando les choca.
create or replace function public.equipos_del_grupo(p_group_id uuid)
returns table (
  id            uuid,
  name          text,
  short_name    text,
  logo_url      text,
  primary_color text,
  jugadores     bigint,
  tiene_capitan boolean,
  es_mi_equipo  boolean
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    t.id, t.name, t.short_name, t.logo_url, t.primary_color,
    (select count(*) from public.players p
      where p.team_id = t.id and p.is_active),
    exists (select 1 from public.team_members tm
            where tm.team_id = t.id and tm.is_captain),
    public.is_team_member(t.id)
  from public.teams t
  where t.group_id = p_group_id
    and public.es_miembro_del_grupo(p_group_id)   -- si no eres del grupo, lista vacia
  order by t.name;
$$;

grant execute on function public.equipos_del_grupo(uuid) to authenticated;

comment on function public.equipos_del_grupo is
  'Equipos de un grupo, para elegir rival. Devuelve vacío si no perteneces al grupo.';

-- ---------------------------------------------------------------------
-- 4. Tabla de posiciones del grupo
-- ---------------------------------------------------------------------
-- Si los equipos de un grupo se enfrentan entre si, la liga necesita su
-- tabla. Cuenta solo partidos terminados entre equipos del mismo grupo.
drop view if exists public.tabla_del_grupo;
create view public.tabla_del_grupo
with (security_invoker = true)
as
with resultados as (
  -- Cada partido aporta una fila por equipo.
  select m.team_id                        as equipo_id,
         t.group_id,
         m.team_score                     as favor,
         m.opponent_score                 as contra
  from public.matches m
  join public.teams t on t.id = m.team_id
  where m.status = 'finished'
    and m.opponent_team_id is not null
    and t.group_id is not null

  union all

  select m.opponent_team_id,
         t.group_id,
         m.opponent_score,
         m.team_score
  from public.matches m
  join public.teams t on t.id = m.opponent_team_id
  where m.status = 'finished'
    and m.opponent_team_id is not null
    and t.group_id is not null
)
select
  r.group_id,
  r.equipo_id,
  t.name                                              as equipo,
  count(*)                                            as jugados,
  count(*) filter (where r.favor > r.contra)           as ganados,
  count(*) filter (where r.favor = r.contra)           as empatados,
  count(*) filter (where r.favor < r.contra)           as perdidos,
  sum(r.favor)                                        as goles_a_favor,
  sum(r.contra)                                       as goles_en_contra,
  sum(r.favor) - sum(r.contra)                        as diferencia,
  count(*) filter (where r.favor > r.contra) * 3
    + count(*) filter (where r.favor = r.contra)      as puntos
from resultados r
join public.teams t on t.id = r.equipo_id
group by r.group_id, r.equipo_id, t.name;

comment on view public.tabla_del_grupo is
  'Posiciones de la liga. Ordenar por puntos desc, diferencia desc, goles_a_favor desc.';

grant select on public.tabla_del_grupo to authenticated;


-- #####################################################################
-- # 20260823190000_13_cuenta_dev.sql
-- #####################################################################

-- =====================================================================
-- Anotar Gol - 13 | Cuenta de desarrollador (superadministrador)
-- =====================================================================
-- Requisito del 23/08/2026:
--
--   Existe una cuenta de dev que puede ver y editar TODOS los grupos y
--   equipos, y que es la UNICA que puede crear un grupo nuevo. El resto
--   de la gente solo entra con clave de invitacion.
--
-- Como se concede:
--   No hay forma de volverse dev desde la app. Se inserta a mano en la
--   base, que es justo lo que se espera de un superadministrador:
--
--     insert into public.app_admins (user_id, note)
--     values ('<uuid del usuario>', 'cuenta de desarrollo');
--
--   Para saber el uuid: select id, email from auth.users where email = '...';
--
-- Por que se hace con una tabla y no con una columna en `profiles`:
--   `profiles` lo puede actualizar su dueño (politica profiles_update_self).
--   Una bandera ahi seria auto-otorgable. Esta tabla, en cambio, solo la
--   escribe alguien que ya es dev, o el equipo desde el panel de Supabase.
-- =====================================================================

create table if not exists public.app_admins (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  note       text,
  created_at timestamptz not null default now()
);

comment on table public.app_admins is
  'Cuentas con poder sobre toda la plataforma. Se otorga solo desde la base.';

alter table public.app_admins enable row level security;

create or replace function public.es_dev()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.app_admins a where a.user_id = auth.uid()
  );
$$;

grant execute on function public.es_dev() to authenticated;

-- Solo un dev ve y toca la lista de devs.
drop policy if exists app_admins_select on public.app_admins;
create policy app_admins_select on public.app_admins
  for select to authenticated using (public.es_dev());

drop policy if exists app_admins_write on public.app_admins;
create policy app_admins_write on public.app_admins
  for all to authenticated
  using (public.es_dev())
  with check (public.es_dev());

-- ---------------------------------------------------------------------
-- El poder del dev se inyecta en las funciones de permisos
-- ---------------------------------------------------------------------
-- Se toca aqui y no politica por politica: estas funciones son el unico
-- punto por el que pasa todo el modelo de acceso, asi que una linea en
-- cada una cubre las 60 y pico politicas sin repetir la condicion.

create or replace function public.es_miembro_del_grupo(p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.es_dev() or exists (
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
  select public.es_dev() or exists (
    select 1 from public.group_members gm
    where gm.group_id = p_group_id
      and gm.user_id = auth.uid()
      and gm.role = 'group_admin'
  );
$$;

create or replace function public.can_view_team(p_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.es_dev() or exists (
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

create or replace function public.can_edit_team(p_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.es_dev()
      or coalesce(public.team_role_of(p_team_id) in ('owner', 'admin', 'coach'), false);
$$;

create or replace function public.can_admin_team(p_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.es_dev()
      or coalesce(public.team_role_of(p_team_id) in ('owner', 'admin'), false);
$$;

create or replace function public.can_edit_squad(p_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.es_dev()
      or coalesce(
           public.team_role_of(p_team_id) in ('owner', 'admin', 'coach', 'player'),
           false);
$$;

create or replace function public.can_captain(p_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.es_dev() or exists (
    select 1
    from public.team_members tm
    where tm.team_id = p_team_id
      and tm.user_id = auth.uid()
      and (tm.is_captain or tm.role in ('owner', 'admin'))
  );
$$;

-- ---------------------------------------------------------------------
-- Politicas que consultan la membresia directamente
-- ---------------------------------------------------------------------
-- `is_team_member` se deja literal a proposito ("soy miembro de verdad"),
-- asi que las politicas que la usan sin pasar por las funciones de
-- arriba necesitan su propia mencion al dev.

drop policy if exists teams_select on public.teams;
create policy teams_select on public.teams
  for select to anon, authenticated
  using (
    public.es_dev()
    or public.is_team_member(id)
    or (group_id is not null
        and is_discoverable
        and public.es_miembro_del_grupo(group_id))
    or (group_id is null and is_public)
  );

drop policy if exists team_members_select on public.team_members;
create policy team_members_select on public.team_members
  for select to authenticated
  using (public.es_dev() or public.is_team_member(team_id));

drop policy if exists challenges_select on public.challenges;
create policy challenges_select on public.challenges
  for select to authenticated
  using (
    public.es_dev()
    or public.is_team_member(from_team_id)
    or public.is_team_member(to_team_id)
  );

-- El chat interno se abre al dev SOLO para moderar. Las dos tiendas
-- exigen poder atender denuncias de contenido en apps con chat; sin un
-- camino para revisarlo, esa exigencia no se puede cumplir.
drop policy if exists team_messages_select on public.team_messages;
create policy team_messages_select on public.team_messages
  for select to authenticated
  using (public.es_dev() or public.is_team_member(team_id));

drop policy if exists team_messages_delete on public.team_messages;
create policy team_messages_delete on public.team_messages
  for delete to authenticated
  using (public.es_dev() or user_id = auth.uid() or public.can_admin_team(team_id));

-- ---------------------------------------------------------------------
-- Crear grupos queda reservado al dev
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

  if not public.es_dev() then
    raise exception 'Solo la cuenta de desarrollo puede crear grupos'
      using errcode = '42501',
            hint = 'Pide una clave de invitación a quien administra el grupo.';
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

  insert into public.group_invites (group_id, code, created_by)
  values (v_grupo.id, public.generar_codigo_invitacion(), auth.uid());

  return v_grupo;
end;
$$;

-- Nadie inserta grupos por la puerta de atras saltandose el RPC.
drop policy if exists groups_insert on public.groups;
create policy groups_insert on public.groups
  for insert to authenticated
  with check (public.es_dev());

grant execute on function public.crear_grupo(text, text) to authenticated;

-- ---------------------------------------------------------------------
-- Panel del dev
-- ---------------------------------------------------------------------
-- Todos los grupos con su tamaño, para la pantalla de administracion.
-- La vista es security_invoker: a quien no sea dev le devuelve vacio,
-- porque groups_select ya lo filtra.
drop view if exists public.panel_dev_grupos;
create view public.panel_dev_grupos
with (security_invoker = true)
as
select
  g.id,
  g.name,
  g.slug,
  g.description,
  g.created_at,
  (select count(*) from public.teams t where t.group_id = g.id)          as equipos,
  (select count(*) from public.group_members gm where gm.group_id = g.id) as miembros,
  (select count(*) from public.group_invites gi
     where gi.group_id = g.id and gi.is_active)                          as invitaciones_activas,
  (select count(*) from public.matches m
     join public.teams t2 on t2.id = m.team_id
    where t2.group_id = g.id)                                            as partidos
from public.groups g;

grant select on public.panel_dev_grupos to authenticated;

comment on view public.panel_dev_grupos is
  'Resumen de todos los grupos. Solo devuelve filas a la cuenta de desarrollo.';


-- #####################################################################
-- # 20260823200000_14_panel_dev_solo_dev.sql
-- #####################################################################

-- =====================================================================
-- Anotar Gol - 14 | El panel del dev es solo del dev
-- =====================================================================
-- Al probar la migracion 13 aparecio esto:
--
--   filas del panel para un usuario normal: 1
--
-- La vista `panel_dev_grupos` es security_invoker, asi que heredaba la
-- politica `groups_select`: un miembro del grupo ve su propia fila. No
-- es una fuga entre grupos, pero expone a cualquier integrante el conteo
-- de miembros y de invitaciones activas de su liga, que es informacion
-- de administracion.
--
-- Se agrega el filtro explicito: si no eres dev, la vista esta vacia.
-- =====================================================================

drop view if exists public.panel_dev_grupos;
create view public.panel_dev_grupos
with (security_invoker = true)
as
select
  g.id,
  g.name,
  g.slug,
  g.description,
  g.created_at,
  (select count(*) from public.teams t where t.group_id = g.id)          as equipos,
  (select count(*) from public.group_members gm where gm.group_id = g.id) as miembros,
  (select count(*) from public.group_invites gi
     where gi.group_id = g.id and gi.is_active)                          as invitaciones_activas,
  (select count(*) from public.matches m
     join public.teams t2 on t2.id = m.team_id
    where t2.group_id = g.id)                                            as partidos
from public.groups g
where public.es_dev();

grant select on public.panel_dev_grupos to authenticated;

comment on view public.panel_dev_grupos is
  'Resumen de todos los grupos. Vacía para quien no sea la cuenta de desarrollo.';


-- #####################################################################
-- # 20260823210000_15_el_capitan_crea_su_equipo.sql
-- #####################################################################

-- =====================================================================
-- Anotar Gol - 15 | Quien crea el equipo queda de capitán
-- =====================================================================
-- Pregunta de diseño: ¿cómo hace el capitán para crear su equipo?
--
-- El nudo es que un capitán lo es DE un equipo, y el equipo todavía no
-- existe. Así que el orden real es al revés: alguien entra al grupo con
-- la clave, crea su equipo, y por crearlo queda como dueño y capitán.
--
-- Hueco que se arregla aquí:
--   `handle_new_team` dejaba al creador como `owner`, pero nunca marcaba
--   `is_captain`. Resultado: un equipo recién creado no tenía capitán, y
--   sin capitán no se puede retar ni ser retado. En las pruebas hubo que
--   ponerlo a mano; esa era la señal.
--
-- Y un límite, para que la puerta abierta no se convierta en un problema:
--   quien entra con una clave puede crear UN equipo en ese grupo. El
--   administrador del grupo puede subir ese número si hace falta.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Cuántos equipos puede crear cada persona en un grupo
-- ---------------------------------------------------------------------
alter table public.groups
  add column if not exists max_equipos_por_miembro smallint not null default 1;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'groups_max_equipos_chk') then
    alter table public.groups add constraint groups_max_equipos_chk
      check (max_equipos_por_miembro between 1 and 20);
  end if;
end
$$;

comment on column public.groups.max_equipos_por_miembro is
  'Equipos que puede fundar cada miembro en este grupo. Evita que una clave filtrada llene la liga.';

-- ---------------------------------------------------------------------
-- 2. El fundador queda de capitán
-- ---------------------------------------------------------------------
create or replace function public.handle_new_team()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.created_by is not null then
    -- Dueño y capitán: es quien lo fundó y, hasta que diga otra cosa,
    -- quien va a coordinar los partidos.
    insert into public.team_members (team_id, user_id, role, is_captain)
    values (new.id, new.created_by, 'owner', true)
    on conflict (team_id, user_id) do update
      set role = 'owner', is_captain = true;
  end if;

  insert into public.team_settings (team_id)
  values (new.id)
  on conflict (team_id) do nothing;

  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. Pasar la cinta de capitán
-- ---------------------------------------------------------------------
-- Hay un índice único de un capitán por equipo, así que quitar al
-- anterior y poner al nuevo tiene que ocurrir en un solo paso.
create or replace function public.nombrar_capitan(
  p_team_id uuid,
  p_user_id uuid
)
returns public.team_members
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_miembro public.team_members;
begin
  -- Lo decide el capitán actual o la dirección del club.
  if not (public.can_captain(p_team_id) or public.can_admin_team(p_team_id)) then
    raise exception 'Solo el capitán o un administrador del club pueden pasar la cinta'
      using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.team_members
    where team_id = p_team_id and user_id = p_user_id
  ) then
    raise exception 'Esa persona no pertenece al equipo' using errcode = 'P0002';
  end if;

  update public.team_members
  set is_captain = false
  where team_id = p_team_id and is_captain and user_id <> p_user_id;

  update public.team_members
  set is_captain = true
  where team_id = p_team_id and user_id = p_user_id
  returning * into v_miembro;

  return v_miembro;
end;
$$;

grant execute on function public.nombrar_capitan(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 4. create_team respeta el límite del grupo
-- ---------------------------------------------------------------------
create or replace function public.create_team(
  p_name            text,
  p_short_name      text default null,
  p_primary_color   text default '#1B5E20',
  p_secondary_color text default '#FFD700',
  p_is_public       boolean default false,
  p_group_id        uuid default null
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
  v_max       smallint;
  v_tiene     int;
begin
  if auth.uid() is null then
    raise exception 'Debes iniciar sesión para crear un equipo'
      using errcode = '42501';
  end if;

  if p_group_id is not null then
    if not public.es_miembro_del_grupo(p_group_id) then
      raise exception 'No perteneces a ese grupo'
        using errcode = '42501',
              hint = 'Únete al grupo con su clave de invitación antes de crear el equipo.';
    end if;

    -- El dev y el administrador del grupo no tienen tope: son quienes
    -- ordenan la liga.
    if not (public.es_dev() or public.es_admin_del_grupo(p_group_id)) then
      select max_equipos_por_miembro into v_max
      from public.groups where id = p_group_id;

      select count(*) into v_tiene
      from public.teams t
      join public.team_members tm on tm.team_id = t.id
      where t.group_id = p_group_id
        and tm.user_id = auth.uid()
        and tm.role = 'owner';

      if v_tiene >= coalesce(v_max, 1) then
        raise exception 'Ya fundaste % equipo(s) en este grupo', v_tiene
          using errcode = '42501',
                hint = 'Pídele al administrador del grupo que suba el límite o que cree el equipo por ti.';
      end if;
    end if;
  end if;

  v_base_slug := coalesce(nullif(public.slugify(p_name), ''), 'equipo');
  v_slug := v_base_slug;

  while exists (select 1 from public.teams t where t.slug = v_slug) loop
    v_suffix := v_suffix + 1;
    v_slug := v_base_slug || '-' || v_suffix;
  end loop;

  insert into public.teams (
    name, short_name, slug, primary_color, secondary_color,
    is_public, group_id, created_by
  )
  values (
    btrim(p_name), nullif(btrim(coalesce(p_short_name, '')), ''), v_slug,
    p_primary_color, p_secondary_color, p_is_public, p_group_id, auth.uid()
  )
  returning * into v_team;

  return v_team;
end;
$$;

grant execute on function public.create_team(text, text, text, text, boolean, uuid)
  to authenticated;

-- ---------------------------------------------------------------------
-- 5. ¿Puedo fundar un equipo en este grupo?
-- ---------------------------------------------------------------------
-- Para que la app muestre u oculte el botón en vez de dejar que el
-- usuario descubra el límite chocándose con un error.
create or replace function public.puedo_crear_equipo(p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    public.es_miembro_del_grupo(p_group_id)
    and (
      public.es_dev()
      or public.es_admin_del_grupo(p_group_id)
      or (
        select count(*)
        from public.teams t
        join public.team_members tm on tm.team_id = t.id
        where t.group_id = p_group_id
          and tm.user_id = auth.uid()
          and tm.role = 'owner'
      ) < coalesce(
        (select max_equipos_por_miembro from public.groups where id = p_group_id),
        1)
    );
$$;

grant execute on function public.puedo_crear_equipo(uuid) to authenticated;


-- #####################################################################
-- # 20260823220000_16_claves_de_capitan.sql
-- #####################################################################

-- =====================================================================
-- Anotar Gol - 16 | Dos tipos de clave: capitán y jugador
-- =====================================================================
-- La idea que cierra el diseño: la clave de invitación no solo abre la
-- puerta del grupo, además dice a qué vienes.
--
--   CLAVE DE CAPITÁN  -> entras al grupo Y puedes fundar tu equipo.
--                        Quedas como dueño y capitán de ese equipo.
--   CLAVE DE JUGADOR  -> entras al grupo pero no fundas nada. Te sumas
--                        a un equipo que ya existe.
--
-- Encaja con el resto: el dev crea el grupo, reparte unas pocas claves
-- de capitán (una por club que quiera en la liga) y muchas de jugador.
-- Nadie entra sin código, y el código ya trae el permiso puesto. No hace
-- falta un paso extra de "ahora nómbrame capitán".
--
-- El tope por miembro de la migración 15 se conserva como red de
-- seguridad: aunque una clave de capitán se filtre y la usen diez
-- personas, cada una funda como máximo lo que permita el grupo.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. La clave dice para qué es
-- ---------------------------------------------------------------------
alter table public.group_invites
  add column if not exists para_capitan boolean not null default false;

comment on column public.group_invites.para_capitan is
  'true = quien la canjee podrá fundar su equipo y será su capitán.';

-- El permiso queda escrito en la membresía, no se recalcula desde la
-- invitación: así revocarlo después es un update y no hay que rastrear
-- con qué código entró cada quien.
alter table public.group_members
  add column if not exists puede_fundar_equipo boolean not null default false;

comment on column public.group_members.puede_fundar_equipo is
  'Se enciende al entrar con una clave de capitán. El admin puede quitarlo.';

-- ---------------------------------------------------------------------
-- 2. Crear la clave, diciendo de qué tipo es
-- ---------------------------------------------------------------------
create or replace function public.crear_invitacion(
  p_group_id     uuid,
  p_max_usos     int     default null,
  p_dias         int     default null,
  p_para_capitan boolean default false
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

  insert into public.group_invites (
    group_id, code, created_by, max_uses, expires_at, para_capitan
  )
  values (
    p_group_id,
    public.generar_codigo_invitacion(),
    auth.uid(),
    p_max_usos,
    case when p_dias is null then null else now() + make_interval(days => p_dias) end,
    coalesce(p_para_capitan, false)
  )
  returning * into v_inv;

  return v_inv;
end;
$$;

-- La firma vieja de 3 argumentos se retira para que no queden dos
-- funciones compitiendo por el mismo nombre.
drop function if exists public.crear_invitacion(uuid, int, int);

grant execute on function public.crear_invitacion(uuid, int, int, boolean)
  to authenticated;

-- ---------------------------------------------------------------------
-- 3. Canjear: el código trae el permiso puesto
-- ---------------------------------------------------------------------
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

  if exists (
    select 1 from public.group_members
    where group_id = v_inv.group_id and user_id = auth.uid()
  ) then
    -- Ya estabas dentro. Si esta clave es de capitán, sube el permiso;
    -- nunca lo baja, para que canjear una clave de jugador no le quite
    -- la condición de capitán a quien ya la tenía.
    if v_inv.para_capitan then
      update public.group_members
      set puede_fundar_equipo = true
      where group_id = v_inv.group_id and user_id = auth.uid();
      update public.group_invites set uses = uses + 1 where id = v_inv.id;
    end if;
    return v_grupo;
  end if;

  insert into public.group_members (group_id, user_id, role, puede_fundar_equipo)
  values (v_inv.group_id, auth.uid(), 'member', v_inv.para_capitan);

  update public.group_invites set uses = uses + 1 where id = v_inv.id;

  return v_grupo;
end;
$$;

grant execute on function public.unirse_con_codigo(text) to authenticated;

-- ---------------------------------------------------------------------
-- 4. Fundar equipo exige haber entrado con clave de capitán
-- ---------------------------------------------------------------------
create or replace function public.puedo_crear_equipo(p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    public.es_dev()
    or public.es_admin_del_grupo(p_group_id)
    or (
      exists (
        select 1 from public.group_members gm
        where gm.group_id = p_group_id
          and gm.user_id = auth.uid()
          and gm.puede_fundar_equipo
      )
      and (
        select count(*)
        from public.teams t
        join public.team_members tm on tm.team_id = t.id
        where t.group_id = p_group_id
          and tm.user_id = auth.uid()
          and tm.role = 'owner'
      ) < coalesce(
        (select max_equipos_por_miembro from public.groups where id = p_group_id),
        1)
    );
$$;

grant execute on function public.puedo_crear_equipo(uuid) to authenticated;

create or replace function public.create_team(
  p_name            text,
  p_short_name      text default null,
  p_primary_color   text default '#1B5E20',
  p_secondary_color text default '#FFD700',
  p_is_public       boolean default false,
  p_group_id        uuid default null
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
    raise exception 'Debes iniciar sesión para crear un equipo'
      using errcode = '42501';
  end if;

  if p_group_id is not null then
    if not public.es_miembro_del_grupo(p_group_id) then
      raise exception 'No perteneces a ese grupo'
        using errcode = '42501',
              hint = 'Únete al grupo con su clave de invitación antes de crear el equipo.';
    end if;

    if not public.puedo_crear_equipo(p_group_id) then
      raise exception 'Necesitas una clave de capitán para fundar un equipo en este grupo'
        using errcode = '42501',
              hint = 'Pídesela a quien administra el grupo. Con una clave de jugador solo puedes sumarte a un equipo que ya exista.';
    end if;
  end if;

  v_base_slug := coalesce(nullif(public.slugify(p_name), ''), 'equipo');
  v_slug := v_base_slug;

  while exists (select 1 from public.teams t where t.slug = v_slug) loop
    v_suffix := v_suffix + 1;
    v_slug := v_base_slug || '-' || v_suffix;
  end loop;

  insert into public.teams (
    name, short_name, slug, primary_color, secondary_color,
    is_public, group_id, created_by
  )
  values (
    btrim(p_name), nullif(btrim(coalesce(p_short_name, '')), ''), v_slug,
    p_primary_color, p_secondary_color, p_is_public, p_group_id, auth.uid()
  )
  returning * into v_team;

  return v_team;
end;
$$;

grant execute on function public.create_team(text, text, text, text, boolean, uuid)
  to authenticated;

-- ---------------------------------------------------------------------
-- 5. El admin puede dar o quitar el permiso a mano
-- ---------------------------------------------------------------------
create or replace function public.permitir_fundar_equipo(
  p_group_id uuid,
  p_user_id  uuid,
  p_permitir boolean default true
)
returns public.group_members
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_m public.group_members;
begin
  if not public.es_admin_del_grupo(p_group_id) then
    raise exception 'Solo un administrador del grupo puede cambiar esto'
      using errcode = '42501';
  end if;

  update public.group_members
  set puede_fundar_equipo = p_permitir
  where group_id = p_group_id and user_id = p_user_id
  returning * into v_m;

  if v_m.user_id is null then
    raise exception 'Esa persona no pertenece al grupo' using errcode = 'P0002';
  end if;

  return v_m;
end;
$$;

grant execute on function public.permitir_fundar_equipo(uuid, uuid, boolean)
  to authenticated;


-- #####################################################################
-- # 20260823230000_17_solicitar_fundar_equipo.sql
-- #####################################################################

-- =====================================================================
-- Anotar Gol - 17 | Pedirle permiso a la administración para fundar
-- =====================================================================
-- Complemento de la clave de capitán: quien entró con clave de jugador
-- y sí quiere armar su equipo no queda en un callejón sin salida. Pide
-- permiso desde la app y el administrador del grupo aprueba o rechaza.
--
-- Aprobar es exactamente lo mismo que entregarle una clave de capitán:
-- enciende `group_members.puede_fundar_equipo`.
-- =====================================================================

do $$
begin
  if not exists (select 1 from pg_type where typname = 'estado_solicitud') then
    create type public.estado_solicitud as enum ('pendiente', 'aprobada', 'rechazada');
  end if;
end
$$;

create table if not exists public.solicitudes_equipo (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references public.groups (id) on delete cascade,
  user_id      uuid not null references auth.users (id) on delete cascade,
  mensaje      text check (char_length(mensaje) <= 300),
  nombre_equipo text check (char_length(btrim(nombre_equipo)) <= 80),
  estado       public.estado_solicitud not null default 'pendiente',
  resuelta_por uuid references auth.users (id) on delete set null,
  resuelta_at  timestamptz,
  created_at   timestamptz not null default now()
);

-- Una solicitud pendiente por persona y grupo: no se spamea al admin.
create unique index if not exists solicitudes_una_pendiente
  on public.solicitudes_equipo (group_id, user_id) where estado = 'pendiente';

create index if not exists solicitudes_grupo_idx
  on public.solicitudes_equipo (group_id, estado);

alter table public.solicitudes_equipo enable row level security;

-- Ves las tuyas; el admin ve las de su grupo.
drop policy if exists solicitudes_select on public.solicitudes_equipo;
create policy solicitudes_select on public.solicitudes_equipo
  for select to authenticated
  using (user_id = auth.uid() or public.es_admin_del_grupo(group_id));

drop policy if exists solicitudes_insert on public.solicitudes_equipo;
create policy solicitudes_insert on public.solicitudes_equipo
  for insert to authenticated
  with check (user_id = auth.uid() and public.es_miembro_del_grupo(group_id));

drop policy if exists solicitudes_update on public.solicitudes_equipo;
create policy solicitudes_update on public.solicitudes_equipo
  for update to authenticated
  using (public.es_admin_del_grupo(group_id))
  with check (public.es_admin_del_grupo(group_id));

-- Retirar la propia solicitud.
drop policy if exists solicitudes_delete on public.solicitudes_equipo;
create policy solicitudes_delete on public.solicitudes_equipo
  for delete to authenticated
  using (user_id = auth.uid() and estado = 'pendiente');

create or replace function public.solicitar_fundar_equipo(
  p_group_id      uuid,
  p_nombre_equipo text default null,
  p_mensaje       text default null
)
returns public.solicitudes_equipo
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_s public.solicitudes_equipo;
begin
  if not public.es_miembro_del_grupo(p_group_id) then
    raise exception 'No perteneces a ese grupo' using errcode = '42501';
  end if;

  if public.puedo_crear_equipo(p_group_id) then
    raise exception 'Ya puedes fundar tu equipo, no hace falta pedir permiso'
      using errcode = '23514';
  end if;

  insert into public.solicitudes_equipo (group_id, user_id, nombre_equipo, mensaje)
  values (p_group_id, auth.uid(), nullif(btrim(coalesce(p_nombre_equipo,'')),''), p_mensaje)
  on conflict (group_id, user_id) where estado = 'pendiente'
    do update set mensaje = excluded.mensaje,
                  nombre_equipo = excluded.nombre_equipo
  returning * into v_s;

  return v_s;
end;
$$;

create or replace function public.responder_solicitud(
  p_solicitud_id uuid,
  p_aprobar      boolean
)
returns public.solicitudes_equipo
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_s public.solicitudes_equipo;
begin
  select * into v_s from public.solicitudes_equipo where id = p_solicitud_id;

  if v_s.id is null then
    raise exception 'Esa solicitud no existe' using errcode = 'P0002';
  end if;

  if not public.es_admin_del_grupo(v_s.group_id) then
    raise exception 'Solo un administrador del grupo puede responder'
      using errcode = '42501';
  end if;

  if v_s.estado <> 'pendiente' then
    raise exception 'Esa solicitud ya fue respondida' using errcode = '23514';
  end if;

  if p_aprobar then
    -- Aprobar es entregarle la llave de capitán.
    update public.group_members
    set puede_fundar_equipo = true
    where group_id = v_s.group_id and user_id = v_s.user_id;
  end if;

  update public.solicitudes_equipo
  set estado = case when p_aprobar then 'aprobada' else 'rechazada' end,
      resuelta_por = auth.uid(),
      resuelta_at = now()
  where id = p_solicitud_id
  returning * into v_s;

  return v_s;
end;
$$;

grant execute on function public.solicitar_fundar_equipo(uuid, text, text) to authenticated;
grant execute on function public.responder_solicitud(uuid, boolean)         to authenticated;

-- La bandeja del administrador, con quién pide y qué pide.
drop view if exists public.solicitudes_del_grupo;
create view public.solicitudes_del_grupo
with (security_invoker = true)
as
select
  s.id, s.group_id, s.user_id, s.nombre_equipo, s.mensaje, s.estado,
  s.created_at, s.resuelta_at,
  p.display_name as solicitante,
  p.email        as correo
from public.solicitudes_equipo s
left join public.profiles p on p.id = s.user_id;

grant select on public.solicitudes_del_grupo to authenticated;


-- #####################################################################
-- # 20260824000000_18_clave_de_equipo.sql
-- #####################################################################

-- =====================================================================
-- Anotar Gol - 18 | La segunda clave: entrar a un equipo
-- =====================================================================
-- Hay dos claves, y hacen cosas distintas:
--
--   CLAVE DE GRUPO   (login)  -> entras a la liga. Ves sus equipos, su
--                                cronograma, su tabla. La reparte el
--                                administrador del grupo.
--   CLAVE DE EQUIPO  (club)   -> te sumas a un equipo concreto de esa
--                                liga. La reparte el capitán.
--
-- Detalle de usabilidad que se resuelve aquí:
--   Si te dan la clave del equipo pero nadie te dio la del grupo, no
--   tiene sentido dejarte fuera: pertenecer a un equipo implica estar en
--   su liga. Así que canjear una clave de equipo también te mete en el
--   grupo, como miembro simple y SIN permiso para fundar equipos. La
--   clave es la autorización; pedir dos códigos para un solo acto sería
--   fricción sin ganancia de seguridad.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Generador de códigos compartido
-- ---------------------------------------------------------------------
-- Antes solo miraba `group_invites`. Con dos tablas de códigos hay que
-- comprobar las dos, o un día una clave de equipo chocaría con una de
-- grupo y el canje elegiría la equivocada.
create or replace function public.generar_codigo_invitacion()
returns text
language plpgsql
volatile
set search_path = public, pg_temp
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

    exit when not exists (select 1 from public.group_invites gi where gi.code = v_codigo)
          and not exists (select 1 from public.team_invites ti where ti.code = v_codigo);

    v_intento := v_intento + 1;
    if v_intento > 50 then
      raise exception 'No se pudo generar un código libre';
    end if;
  end loop;

  return v_codigo;
end;
$$;

-- ---------------------------------------------------------------------
-- 2. Claves de equipo
-- ---------------------------------------------------------------------
create table if not exists public.team_invites (
  id         uuid primary key default gen_random_uuid(),
  team_id    uuid not null references public.teams (id) on delete cascade,
  code       text not null unique,
  -- Con qué rol entra quien la canjee. Por defecto jugador: los roles de
  -- mando no se reparten por código.
  rol        public.team_role not null default 'player',
  created_by uuid references auth.users (id) on delete set null,
  max_uses   int,
  uses       int not null default 0,
  expires_at timestamptz,
  is_active  boolean not null default true,
  created_at timestamptz not null default now(),
  constraint team_invites_rol_chk check (rol in ('player', 'coach', 'viewer'))
);

create index if not exists team_invites_team_idx on public.team_invites (team_id);

comment on table public.team_invites is
  'Claves que reparte el capitán para que su gente se sume al equipo.';

alter table public.team_invites enable row level security;

-- Las ve y las crea quien manda en el club.
drop policy if exists team_invites_select on public.team_invites;
create policy team_invites_select on public.team_invites
  for select to authenticated
  using (public.can_captain(team_id) or public.can_admin_team(team_id));

drop policy if exists team_invites_write on public.team_invites;
create policy team_invites_write on public.team_invites
  for all to authenticated
  using (public.can_captain(team_id) or public.can_admin_team(team_id))
  with check (public.can_captain(team_id) or public.can_admin_team(team_id));

-- ---------------------------------------------------------------------
-- 3. Crear la clave del equipo
-- ---------------------------------------------------------------------
create or replace function public.crear_invitacion_equipo(
  p_team_id  uuid,
  p_rol      public.team_role default 'player',
  p_max_usos int default null,
  p_dias     int default null
)
returns public.team_invites
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_inv public.team_invites;
begin
  if not (public.can_captain(p_team_id) or public.can_admin_team(p_team_id)) then
    raise exception 'Solo el capitán o un administrador del club pueden crear claves'
      using errcode = '42501';
  end if;

  if p_rol not in ('player', 'coach', 'viewer') then
    raise exception 'Por código solo se entra como jugador, cuerpo técnico o hincha'
      using errcode = '23514',
            hint = 'Los roles de mando se otorgan a mano desde la gestión del club.';
  end if;

  insert into public.team_invites (
    team_id, code, rol, created_by, max_uses, expires_at
  )
  values (
    p_team_id,
    public.generar_codigo_invitacion(),
    p_rol,
    auth.uid(),
    p_max_usos,
    case when p_dias is null then null else now() + make_interval(days => p_dias) end
  )
  returning * into v_inv;

  return v_inv;
end;
$$;

-- ---------------------------------------------------------------------
-- 4. Canjear la clave del equipo
-- ---------------------------------------------------------------------
create or replace function public.unirse_a_equipo_con_codigo(p_codigo text)
returns public.teams
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_inv    public.team_invites;
  v_equipo public.teams;
begin
  if auth.uid() is null then
    raise exception 'Debes iniciar sesión' using errcode = '42501';
  end if;

  select * into v_inv
  from public.team_invites
  where upper(btrim(code)) = upper(btrim(p_codigo));

  if v_inv.id is null then
    raise exception 'Esa clave de equipo no existe' using errcode = 'P0002';
  end if;

  if not v_inv.is_active then
    raise exception 'Esa clave fue desactivada' using errcode = '42501';
  end if;

  if v_inv.expires_at is not null and v_inv.expires_at < now() then
    raise exception 'Esa clave ya venció' using errcode = '42501';
  end if;

  if v_inv.max_uses is not null and v_inv.uses >= v_inv.max_uses then
    raise exception 'Esa clave ya se usó el máximo de veces' using errcode = '42501';
  end if;

  select * into v_equipo from public.teams where id = v_inv.team_id;

  -- Pertenecer al equipo implica estar en su liga: si falta, se entra
  -- como miembro simple, sin permiso para fundar equipos.
  if v_equipo.group_id is not null
     and not exists (
       select 1 from public.group_members
       where group_id = v_equipo.group_id and user_id = auth.uid()
     ) then
    insert into public.group_members (group_id, user_id, role, puede_fundar_equipo)
    values (v_equipo.group_id, auth.uid(), 'member', false);
  end if;

  -- Ya estabas en el equipo: no se gasta un uso ni se toca tu rol, para
  -- que un jugador que ya es capitán no se degrade al reusar la clave.
  if exists (
    select 1 from public.team_members
    where team_id = v_inv.team_id and user_id = auth.uid()
  ) then
    return v_equipo;
  end if;

  insert into public.team_members (team_id, user_id, role)
  values (v_inv.team_id, auth.uid(), v_inv.rol);

  update public.team_invites set uses = uses + 1 where id = v_inv.id;

  return v_equipo;
end;
$$;

grant execute on function public.crear_invitacion_equipo(uuid, public.team_role, int, int)
  to authenticated;
grant execute on function public.unirse_a_equipo_con_codigo(text) to authenticated;

-- ---------------------------------------------------------------------
-- 5. Canje único: la app no tiene por qué saber qué tipo de clave es
-- ---------------------------------------------------------------------
-- Quien recibe un código por WhatsApp no sabe si es de grupo o de
-- equipo. Esta función lo averigua y hace lo que corresponda.
create or replace function public.canjear_clave(p_codigo text)
returns table (
  tipo       text,
  group_id   uuid,
  group_name text,
  team_id    uuid,
  team_name  text
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_codigo text := upper(btrim(p_codigo));
  v_grupo  public.groups;
  v_equipo public.teams;
begin
  if exists (select 1 from public.group_invites where upper(btrim(code)) = v_codigo) then
    v_grupo := public.unirse_con_codigo(v_codigo);
    return query select 'grupo'::text, v_grupo.id, v_grupo.name, null::uuid, null::text;
    return;
  end if;

  if exists (select 1 from public.team_invites where upper(btrim(code)) = v_codigo) then
    v_equipo := public.unirse_a_equipo_con_codigo(v_codigo);
    select * into v_grupo from public.groups where id = v_equipo.group_id;
    return query select 'equipo'::text, v_grupo.id, v_grupo.name, v_equipo.id, v_equipo.name;
    return;
  end if;

  raise exception 'Esa clave no existe. Revísala con quien te la envió.'
    using errcode = 'P0002';
end;
$$;

grant execute on function public.canjear_clave(text) to authenticated;

comment on function public.canjear_clave is
  'Canjea una clave sin que el usuario tenga que saber si es de grupo o de equipo.';


-- #####################################################################
-- # 20260824010000_19_fix_solicitudes_y_perfiles.sql
-- #####################################################################

-- =====================================================================
-- Anotar Gol - 19 | Dos correcciones de la migración 17
-- =====================================================================
-- Ambas aparecieron al probar el flujo completo contra la base.
--
-- 1. responder_solicitud fallaba con:
--      column "estado" is of type estado_solicitud but expression is of
--      type text
--    El CASE devolvía texto sin castear al enum. Se arregla con el cast
--    explícito.
--
-- 2. La bandeja del administrador mostraba `solicitante: null`.
--    La vista es security_invoker y `profiles_select` solo dejaba ver el
--    perfil propio o el de compañeros de EQUIPO. El administrador de un
--    grupo no comparte equipo con quien le escribe, así que veía la
--    solicitud pero no el nombre de quien la manda: inservible para
--    decidir. Se agrega la visibilidad por GRUPO.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. El cast que faltaba
-- ---------------------------------------------------------------------
create or replace function public.responder_solicitud(
  p_solicitud_id uuid,
  p_aprobar      boolean
)
returns public.solicitudes_equipo
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_s public.solicitudes_equipo;
begin
  select * into v_s from public.solicitudes_equipo where id = p_solicitud_id;

  if v_s.id is null then
    raise exception 'Esa solicitud no existe' using errcode = 'P0002';
  end if;

  if not public.es_admin_del_grupo(v_s.group_id) then
    raise exception 'Solo un administrador del grupo puede responder'
      using errcode = '42501';
  end if;

  if v_s.estado <> 'pendiente' then
    raise exception 'Esa solicitud ya fue respondida' using errcode = '23514';
  end if;

  if p_aprobar then
    update public.group_members
    set puede_fundar_equipo = true
    where group_id = v_s.group_id and user_id = v_s.user_id;
  end if;

  update public.solicitudes_equipo
  set estado = (case when p_aprobar then 'aprobada' else 'rechazada' end)
                 ::public.estado_solicitud,
      resuelta_por = auth.uid(),
      resuelta_at = now()
  where id = p_solicitud_id
  returning * into v_s;

  return v_s;
end;
$$;

grant execute on function public.responder_solicitud(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------
-- 2. Ver el nombre de la gente de tu grupo
-- ---------------------------------------------------------------------
create or replace function public.comparte_grupo_conmigo(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.group_members mio
    join public.group_members suyo on suyo.group_id = mio.group_id
    where mio.user_id = auth.uid()
      and suyo.user_id = p_user_id
  );
$$;

grant execute on function public.comparte_grupo_conmigo(uuid) to authenticated;

-- El perfil solo tiene nombre, correo y avatar. Dentro de una liga hace
-- falta poder ponerle cara a quien juega, capitanea o pide permiso.
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated
  using (
    id = auth.uid()
    or public.es_dev()
    or public.shares_team_with(id)
    or public.comparte_grupo_conmigo(id)
  );


-- #####################################################################
-- # 20260824020000_20_cedulas_y_plantilla_obligatoria.sql
-- #####################################################################

-- =====================================================================
-- Anotar Gol - 20 | Cédulas: la ficha del jugador y su cuenta
-- =====================================================================
-- Requisito del 24/08/2026:
--
--   * La cuenta se crea con la cédula (10 dígitos).
--   * Al registrarse, la base comprueba si esa cédula ya está cargada
--     como jugador en algún equipo, y le entrega su ficha.
--   * Para fundar un equipo hay que cargar los 11 jugadores obligatorios
--     con su cédula y su posición.
--   * Si el capitán repite posiciones, es cosa suya: se avisa, no se
--     bloquea.
--
-- El orden que esto habilita es el natural de un club: el capitán arma
-- la plantilla por cédula ANTES de que su gente se registre, y cada
-- jugador, al crear su cuenta, aparece ya fichado.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Validación real de la cédula ecuatoriana
-- ---------------------------------------------------------------------
-- No basta con "que tenga 10 dígitos": eso deja pasar cualquier número
-- inventado, y entonces la cédula no sirve para identificar a nadie.
-- Se valida provincia, tipo y dígito verificador (módulo 10).
--
-- Comprobado con 1750959676:
--   coeficientes 2,1,2,1,2,1,2,1,2 -> suma 44 -> (10 - 4) % 10 = 6  OK
create or replace function public.es_cedula_valida(p_cedula text)
returns boolean
language plpgsql
immutable
as $$
declare
  v_c        text := btrim(coalesce(p_cedula, ''));
  v_prov     int;
  v_tercero  int;
  v_suma     int := 0;
  v_digito   int;
  v_valor    int;
  i          int;
begin
  if v_c !~ '^[0-9]{10}$' then
    return false;
  end if;

  -- Provincia: 01 a 24, o 30 para quienes se inscriben en el exterior.
  v_prov := substr(v_c, 1, 2)::int;
  if not (v_prov between 1 and 24) and v_prov <> 30 then
    return false;
  end if;

  -- Tercer dígito menor que 6 = persona natural.
  v_tercero := substr(v_c, 3, 1)::int;
  if v_tercero >= 6 then
    return false;
  end if;

  -- Dígito verificador: coeficientes 2,1,2,1,2,1,2,1,2 sobre los nueve
  -- primeros; si el producto pasa de 9 se le restan 9.
  for i in 1..9 loop
    v_valor := substr(v_c, i, 1)::int * (case when i % 2 = 1 then 2 else 1 end);
    if v_valor > 9 then
      v_valor := v_valor - 9;
    end if;
    v_suma := v_suma + v_valor;
  end loop;

  v_digito := (10 - (v_suma % 10)) % 10;

  return v_digito = substr(v_c, 10, 1)::int;
end;
$$;

comment on function public.es_cedula_valida is
  'Valida cédula ecuatoriana: provincia, tipo y dígito verificador módulo 10.';

grant execute on function public.es_cedula_valida(text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 2. La cédula en la ficha y en la cuenta
-- ---------------------------------------------------------------------
alter table public.players
  add column if not exists cedula  text,
  add column if not exists user_id uuid references auth.users (id) on delete set null;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'players_cedula_chk') then
    alter table public.players add constraint players_cedula_chk
      check (cedula is null or public.es_cedula_valida(cedula));
  end if;
end
$$;

-- Una cédula no puede estar dos veces en el mismo equipo.
create unique index if not exists players_cedula_por_equipo
  on public.players (team_id, cedula) where cedula is not null;

create index if not exists players_cedula_idx  on public.players (cedula);
create index if not exists players_user_idx    on public.players (user_id);

comment on column public.players.cedula is
  'Cédula del jugador. Es lo que une la ficha con la cuenta cuando se registra.';
comment on column public.players.user_id is
  'Cuenta que reclamó esta ficha. Se llena solo al registrarse con la misma cédula.';

alter table public.profiles
  add column if not exists cedula text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'profiles_cedula_chk') then
    alter table public.profiles add constraint profiles_cedula_chk
      check (cedula is null or public.es_cedula_valida(cedula));
  end if;
end
$$;

-- Una cédula, una cuenta.
create unique index if not exists profiles_cedula_uniq
  on public.profiles (cedula) where cedula is not null;

-- ---------------------------------------------------------------------
-- 3. Al registrarse, se le entregan sus fichas
-- ---------------------------------------------------------------------
create or replace function public.vincular_fichas_por_cedula(p_user_id uuid)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_cedula text;
  v_n      int;
begin
  select cedula into v_cedula from public.profiles where id = p_user_id;
  if v_cedula is null then
    return 0;
  end if;

  update public.players
  set user_id = p_user_id
  where cedula = v_cedula and user_id is distinct from p_user_id;

  get diagnostics v_n = row_count;

  -- Estar fichado en un equipo es ser parte del equipo. Si el capitán ya
  -- te cargó, no tienes que pedir permiso para entrar.
  insert into public.team_members (team_id, user_id, role)
  select p.team_id, p_user_id, 'player'
  from public.players p
  where p.cedula = v_cedula
  on conflict (team_id, user_id) do nothing;

  -- Y al equipo se llega por su grupo.
  insert into public.group_members (group_id, user_id, role, puede_fundar_equipo)
  select distinct t.group_id, p_user_id, 'member', false
  from public.players p
  join public.teams t on t.id = p.team_id
  where p.cedula = v_cedula and t.group_id is not null
  on conflict (group_id, user_id) do nothing;

  return v_n;
end;
$$;

grant execute on function public.vincular_fichas_por_cedula(uuid) to authenticated;

-- El perfil ahora guarda la cédula que venga en el registro, y de paso
-- reclama las fichas que le correspondan.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_cedula text := nullif(btrim(coalesce(new.raw_user_meta_data ->> 'cedula', '')), '');
begin
  if v_cedula is not null and not public.es_cedula_valida(v_cedula) then
    v_cedula := null;   -- no se guarda basura; la app ya la valida antes
  end if;

  insert into public.profiles (id, display_name, email, avatar_url, cedula)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data ->> 'display_name',
      new.raw_user_meta_data ->> 'full_name',
      split_part(coalesce(new.email, 'hincha'), '@', 1)
    ),
    new.email,
    new.raw_user_meta_data ->> 'avatar_url',
    v_cedula
  )
  on conflict (id) do nothing;

  if v_cedula is not null then
    perform public.vincular_fichas_por_cedula(new.id);
  end if;

  return new;
end;
$$;

-- Para quien ya tenía cuenta y agrega la cédula después.
create or replace function public.registrar_mi_cedula(p_cedula text)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_c text := btrim(coalesce(p_cedula, ''));
begin
  if auth.uid() is null then
    raise exception 'Debes iniciar sesión' using errcode = '42501';
  end if;

  if not public.es_cedula_valida(v_c) then
    raise exception 'Esa cédula no es válida'
      using errcode = '23514',
            hint = 'Son 10 dígitos y el último es el verificador.';
  end if;

  if exists (select 1 from public.profiles where cedula = v_c and id <> auth.uid()) then
    raise exception 'Esa cédula ya está registrada en otra cuenta'
      using errcode = '23505';
  end if;

  update public.profiles set cedula = v_c where id = auth.uid();

  return public.vincular_fichas_por_cedula(auth.uid());
end;
$$;

grant execute on function public.registrar_mi_cedula(text) to authenticated;

-- ---------------------------------------------------------------------
-- 4. Los 11 obligatorios
-- ---------------------------------------------------------------------
create or replace function public.equipo_habilitado(p_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select (
    select count(*)
    from public.players p
    where p.team_id = p_team_id
      and p.is_active
      and p.cedula is not null
  ) >= 11;
$$;

grant execute on function public.equipo_habilitado(uuid) to authenticated;

comment on function public.equipo_habilitado is
  'Un equipo puede jugar cuando tiene 11 jugadores activos con cédula cargada.';

-- Avisos, no bloqueos. Las posiciones repetidas son decisión del
-- capitán; lo que sí impide jugar es no llegar a 11 con cédula.
create or replace function public.avisos_de_plantilla(p_team_id uuid)
returns table (
  tipo     text,     -- 'bloqueo' | 'aviso'
  mensaje  text
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_total    int;
  v_con_ced  int;
  v_porteros int;
  r          record;
begin
  select count(*) filter (where is_active),
         count(*) filter (where is_active and cedula is not null),
         count(*) filter (where is_active and position = 'GK')
    into v_total, v_con_ced, v_porteros
  from public.players where team_id = p_team_id;

  if v_con_ced < 11 then
    return query select 'bloqueo'::text,
      format('Faltan %s jugadores con cédula para completar los 11 obligatorios.',
             11 - v_con_ced);
  end if;

  if v_total > v_con_ced then
    return query select 'aviso'::text,
      format('%s jugador(es) sin cédula: no cuentan para los 11.',
             v_total - v_con_ced);
  end if;

  if v_porteros = 0 then
    return query select 'aviso'::text, 'No hay ningún portero en la plantilla.';
  elsif v_porteros > 1 then
    return query select 'aviso'::text,
      format('Hay %s porteros. Normalmente juega uno.', v_porteros);
  end if;

  -- Posiciones repetidas: se avisa y se sigue.
  for r in
    select position_detail, count(*) n
    from public.players
    where team_id = p_team_id and is_active and position_detail is not null
    group by position_detail having count(*) > 1
  loop
    return query select 'aviso'::text,
      format('%s jugadores puestos como "%s".', r.n, r.position_detail);
  end loop;

  return;
end;
$$;

grant execute on function public.avisos_de_plantilla(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 5. Sin los 11, no se juega
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
  v_reto    public.challenges;
  v_grupo_a uuid;
  v_grupo_b uuid;
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

  if v_grupo_a is distinct from v_grupo_b then
    raise exception 'Solo puedes retar a equipos de tu mismo grupo'
      using errcode = '42501';
  end if;

  if not public.equipo_habilitado(p_from_team_id) then
    raise exception 'Tu equipo todavía no tiene los 11 jugadores con cédula'
      using errcode = '23514',
            hint = 'Completa la plantilla antes de retar.';
  end if;

  if not public.equipo_habilitado(p_to_team_id) then
    raise exception 'Ese equipo todavía no completó sus 11 jugadores'
      using errcode = '23514';
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
-- 6. Estado de la plantilla, para la pantalla del capitán
-- ---------------------------------------------------------------------
drop view if exists public.estado_plantilla;
create view public.estado_plantilla
with (security_invoker = true)
as
select
  t.id                                   as team_id,
  t.name                                 as equipo,
  t.group_id,
  count(p.*) filter (where p.is_active)                          as jugadores,
  count(p.*) filter (where p.is_active and p.cedula is not null) as con_cedula,
  count(p.*) filter (where p.is_active and p.user_id is not null) as ya_registrados,
  greatest(0, 11 - count(p.*) filter (where p.is_active and p.cedula is not null))
                                                                 as faltan,
  public.equipo_habilitado(t.id)                                 as habilitado
from public.teams t
left join public.players p on p.team_id = t.id
group by t.id, t.name, t.group_id;

grant select on public.estado_plantilla to authenticated;

comment on view public.estado_plantilla is
  'Cuánto le falta a cada equipo para poder jugar: 11 jugadores con cédula.';


-- #####################################################################
-- # 20260824030000_21_cedula_es_la_identidad.sql
-- #####################################################################

-- =====================================================================
-- Anotar Gol - 21 | La cédula es el id del jugador
-- =====================================================================
-- Dos reglas pedidas el 24/08/2026:
--
--   * El jugador, ya dentro, puede cambiar su nombre y su dorsal, pero
--     su identidad es la cédula y esa NO se toca. Si la cédula pudiera
--     editarse, la ficha dejaría de ser de quien es y el vínculo con la
--     cuenta se rompería.
--   * El capitán saca a alguien del equipo escribiendo su cédula, con
--     una confirmación de por medio.
--
-- Nota sobre "sacar": es baja lógica, no borrado. Los goles del jugador
-- siguen en el historial y en el ranking, que es lo correcto: el gol se
-- metió, aunque después se haya ido del club.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. La cédula no se cambia
-- ---------------------------------------------------------------------
create or replace function public.proteger_cedula_jugador()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- Ponerla cuando faltaba sí se permite: es completar la ficha.
  if old.cedula is not null and new.cedula is distinct from old.cedula then
    raise exception 'La cédula no se puede cambiar: es la identidad del jugador'
      using errcode = '42501',
            hint = 'Si te equivocaste, saca la ficha y créala de nuevo con la cédula correcta.';
  end if;

  -- El jugador puede corregir lo suyo, no cambiarse de equipo ni de dueño.
  if not public.can_edit_squad(old.team_id) then
    if new.team_id is distinct from old.team_id
       or new.user_id is distinct from old.user_id
       or new.is_active is distinct from old.is_active then
      raise exception 'Solo puedes cambiar tu nombre, tu dorsal y tu posición'
        using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists players_proteger_cedula on public.players;
create trigger players_proteger_cedula
  before update on public.players
  for each row execute function public.proteger_cedula_jugador();

-- ---------------------------------------------------------------------
-- 2. El jugador edita su propia ficha
-- ---------------------------------------------------------------------
-- Antes solo podían los roles con permiso sobre la plantilla. Ahora
-- también el dueño de la ficha, limitado por el trigger de arriba.
drop policy if exists players_update on public.players;
create policy players_update on public.players
  for update to authenticated
  using (public.can_edit_squad(team_id) or user_id = auth.uid())
  with check (public.can_edit_squad(team_id) or user_id = auth.uid());

-- ---------------------------------------------------------------------
-- 3. Buscar por cédula antes de sacar
-- ---------------------------------------------------------------------
-- La confirmación necesita mostrar a quién se va a sacar. Preguntar
-- "¿seguro?" sin decir el nombre es una forma de que alguien saque al
-- jugador equivocado.
create or replace function public.buscar_jugador_por_cedula(
  p_team_id uuid,
  p_cedula  text
)
returns table (
  id          uuid,
  full_name   text,
  number      smallint,
  posicion    text,
  cedula      text,
  registrado  boolean,
  goles       bigint
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    p.id,
    p.full_name,
    p.number,
    coalesce(p.position_detail, p.position::text),
    p.cedula,
    p.user_id is not null,
    (select count(*) from public.match_events e
      where e.player_id = p.id and e.type = 'goal' and not e.is_own_goal)
  from public.players p
  where p.team_id = p_team_id
    and p.cedula = btrim(p_cedula)
    and p.is_active
    and public.can_view_team(p_team_id);
$$;

grant execute on function public.buscar_jugador_por_cedula(uuid, text) to authenticated;

-- ---------------------------------------------------------------------
-- 4. Sacar del equipo por cédula
-- ---------------------------------------------------------------------
create or replace function public.sacar_jugador_por_cedula(
  p_team_id uuid,
  p_cedula  text
)
returns public.players
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_j public.players;
begin
  if not (public.can_captain(p_team_id) or public.can_edit_team(p_team_id)) then
    raise exception 'Solo el capitán o el cuerpo técnico pueden sacar jugadores'
      using errcode = '42501';
  end if;

  select * into v_j
  from public.players
  where team_id = p_team_id and cedula = btrim(p_cedula) and is_active;

  if v_j.id is null then
    raise exception 'No hay ningún jugador activo con esa cédula en el equipo'
      using errcode = 'P0002',
            hint = 'Revisa el número: son 10 dígitos.';
  end if;

  -- Baja lógica: los goles se quedan en el historial.
  update public.players
  set is_active = false, user_id = null
  where id = v_j.id
  returning * into v_j;

  -- Y deja de ser miembro del equipo, si tenía cuenta vinculada.
  if v_j.user_id is not null then
    delete from public.team_members
    where team_id = p_team_id and user_id = v_j.user_id;
  end if;

  return v_j;
end;
$$;

grant execute on function public.sacar_jugador_por_cedula(uuid, text) to authenticated;

comment on function public.sacar_jugador_por_cedula is
  'Baja lógica del jugador. Conserva sus goles en el historial y el ranking.';

-- ---------------------------------------------------------------------
-- 5. Mis fichas: en qué equipos juego
-- ---------------------------------------------------------------------
drop view if exists public.mis_fichas;
create view public.mis_fichas
with (security_invoker = true)
as
select
  p.id            as player_id,
  p.team_id,
  t.name          as equipo,
  t.group_id,
  g.name          as grupo,
  p.full_name,
  p.number,
  p.position,
  p.position_detail,
  p.cedula,
  p.is_active,
  exists (
    select 1 from public.team_members tm
    where tm.team_id = p.team_id and tm.user_id = p.user_id and tm.is_captain
  ) as soy_capitan
from public.players p
join public.teams t on t.id = p.team_id
left join public.groups g on g.id = t.group_id
where p.user_id = auth.uid();

grant select on public.mis_fichas to authenticated;

comment on view public.mis_fichas is
  'Los equipos donde el usuario está fichado, con los datos que puede editar.';


-- #####################################################################
-- # 20260824040000_22_reclamar_ficha_y_un_equipo_por_grupo.sql
-- #####################################################################

-- =====================================================================
-- Anotar Gol - 22 | Reclamar la ficha, y un solo equipo por grupo
-- =====================================================================
-- 1. CORRECCIÓN
--    `registrar_mi_cedula` fallaba con "Solo puedes cambiar tu nombre,
--    tu dorsal y tu posición". El trigger de la migración 21 bloquea que
--    alguien sin permiso sobre la plantilla toque `user_id`... y eso es
--    justo lo que hace vincular la ficha con la cuenta.
--    El trigger estaba bien planteado, le faltaba contemplar el caso
--    legítimo: reclamar TU ficha, donde `user_id` pasa de vacío a ti y
--    tu cédula coincide con la de la ficha.
--
-- 2. REGLA NUEVA
--    Un jugador puede estar en dos equipos si son de grupos distintos
--    (liga del barrio y liga del trabajo, por ejemplo), pero JAMÁS en
--    dos equipos del mismo grupo: se enfrentarían entre sí y no se sabría
--    de qué lado juega.
--    No se puede expresar con un índice único porque cruza dos tablas,
--    así que va en un trigger.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Reclamar la ficha propia
-- ---------------------------------------------------------------------
create or replace function public.proteger_cedula_jugador()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_reclama_su_ficha boolean;
begin
  if old.cedula is not null and new.cedula is distinct from old.cedula then
    raise exception 'La cédula no se puede cambiar: es la identidad del jugador'
      using errcode = '42501',
            hint = 'Si te equivocaste, saca la ficha y créala de nuevo con la cédula correcta.';
  end if;

  -- Caso legítimo: la ficha estaba libre y la reclama quien tiene esa
  -- misma cédula en su cuenta.
  v_reclama_su_ficha :=
       old.user_id is null
   and new.user_id is not null
   and old.cedula is not null
   and exists (
         select 1 from public.profiles pr
         where pr.id = new.user_id and pr.cedula = old.cedula);

  if not public.can_edit_squad(old.team_id) and not v_reclama_su_ficha then
    if new.team_id is distinct from old.team_id
       or new.user_id is distinct from old.user_id
       or new.is_active is distinct from old.is_active then
      raise exception 'Solo puedes cambiar tu nombre, tu dorsal y tu posición'
        using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- 2. Un equipo por grupo y por persona
-- ---------------------------------------------------------------------
create or replace function public.un_equipo_por_grupo()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_grupo  uuid;
  v_choque text;
begin
  if new.cedula is null or not new.is_active then
    return new;
  end if;

  select group_id into v_grupo from public.teams where id = new.team_id;

  -- Fuera de un grupo no hay liga que ordenar: se permite.
  if v_grupo is null then
    return new;
  end if;

  select t.name into v_choque
  from public.players p
  join public.teams t on t.id = p.team_id
  where p.cedula = new.cedula
    and p.is_active
    and p.id is distinct from new.id
    and t.group_id = v_grupo
  limit 1;

  if v_choque is not null then
    raise exception 'Esa cédula ya juega en % dentro de este mismo grupo', v_choque
      using errcode = '23505',
            hint = 'Una persona puede estar en varios grupos, pero solo en un equipo de cada uno.';
  end if;

  return new;
end;
$$;

drop trigger if exists players_un_equipo_por_grupo on public.players;
create trigger players_un_equipo_por_grupo
  before insert or update on public.players
  for each row execute function public.un_equipo_por_grupo();

comment on function public.un_equipo_por_grupo is
  'Impide que la misma cédula esté en dos equipos del mismo grupo.';

-- Lo mismo para la membresía: no se puede ser miembro de dos equipos de
-- una misma liga, aunque se llegue por clave de equipo en vez de ficha.
create or replace function public.una_membresia_por_grupo()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_grupo  uuid;
  v_choque text;
begin
  select group_id into v_grupo from public.teams where id = new.team_id;
  if v_grupo is null then
    return new;
  end if;

  select t.name into v_choque
  from public.team_members tm
  join public.teams t on t.id = tm.team_id
  where tm.user_id = new.user_id
    and tm.team_id <> new.team_id
    and t.group_id = v_grupo
  limit 1;

  if v_choque is not null then
    raise exception 'Ya perteneces a % en este grupo', v_choque
      using errcode = '23505',
            hint = 'Sal de ese equipo antes de entrar a otro de la misma liga.';
  end if;

  return new;
end;
$$;

drop trigger if exists team_members_uno_por_grupo on public.team_members;
create trigger team_members_uno_por_grupo
  before insert on public.team_members
  for each row execute function public.una_membresia_por_grupo();


-- #####################################################################
-- # 20260824050000_23_fix_casts_al_vincular.sql
-- #####################################################################

-- =====================================================================
-- Anotar Gol - 23 | Corrección: casts al vincular fichas
-- =====================================================================
-- `registrar_mi_cedula` fallaba con:
--   column "role" is of type group_role but expression is of type text
--
-- Causa: en `insert ... select`, Postgres NO infiere el tipo del literal
-- como sí hace en `insert ... values`. Los 'player' y 'member' llegaban
-- como text a columnas enum.
--
-- Es el mismo tropiezo que en la migración 19 con `estado_solicitud`.
-- Se revisaron todas las migraciones buscando el patrón; estos dos eran
-- los únicos insert-select restantes contra columnas enum.
-- =====================================================================

create or replace function public.vincular_fichas_por_cedula(p_user_id uuid)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_cedula text;
  v_n      int;
begin
  select cedula into v_cedula from public.profiles where id = p_user_id;
  if v_cedula is null then
    return 0;
  end if;

  update public.players
  set user_id = p_user_id
  where cedula = v_cedula and user_id is distinct from p_user_id;

  get diagnostics v_n = row_count;

  -- Estar fichado en un equipo es ser parte del equipo.
  insert into public.team_members (team_id, user_id, role)
  select p.team_id, p_user_id, 'player'::public.team_role
  from public.players p
  where p.cedula = v_cedula and p.is_active
  on conflict (team_id, user_id) do nothing;

  -- Y al equipo se llega por su grupo.
  insert into public.group_members (group_id, user_id, role, puede_fundar_equipo)
  select distinct t.group_id, p_user_id, 'member'::public.group_role, false
  from public.players p
  join public.teams t on t.id = p.team_id
  where p.cedula = v_cedula and p.is_active and t.group_id is not null
  on conflict (group_id, user_id) do nothing;

  return v_n;
end;
$$;

grant execute on function public.vincular_fichas_por_cedula(uuid) to authenticated;


-- #####################################################################
-- # 20260824060000_24_avisos_solo_al_crear.sql
-- #####################################################################

-- =====================================================================
-- Anotar Gol - 24 | Los avisos de posición son solo del armado inicial
-- =====================================================================
-- Ajuste del 24/08/2026: los avisos de posiciones repetidas le sirven al
-- capitán mientras arma los 11 obligatorios. Después estorban: un club
-- con 20 fichados va a tener cuatro laterales derechos y está bien.
--
-- Se resuelve con una marca explícita en vez de adivinar por el número
-- de jugadores: `plantilla_confirmada`. El capitán la pulsa una vez,
-- cuando termina de armar el equipo, y los avisos de composición dejan
-- de aparecer. Lo que sí sigue apareciendo siempre es lo que impide
-- jugar: no llegar a 11 con cédula.
--
-- Por qué una marca y no "cuando llegue a 11": justo al cargar al
-- jugador 11 es cuando el capitán MÁS quiere ver "ojo, tienes dos
-- laterales derechos". Si los avisos se apagaran solos en ese instante,
-- nunca los vería.
-- =====================================================================

alter table public.teams
  add column if not exists plantilla_confirmada boolean not null default false;

comment on column public.teams.plantilla_confirmada is
  'El capitán ya revisó el armado inicial. Apaga los avisos de composición.';

create or replace function public.confirmar_plantilla(p_team_id uuid)
returns public.teams
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_team public.teams;
begin
  if not (public.can_captain(p_team_id) or public.can_edit_team(p_team_id)) then
    raise exception 'Solo el capitán o el cuerpo técnico pueden confirmar la plantilla'
      using errcode = '42501';
  end if;

  if not public.equipo_habilitado(p_team_id) then
    raise exception 'Todavía faltan jugadores con cédula para llegar a 11'
      using errcode = '23514';
  end if;

  update public.teams
  set plantilla_confirmada = true
  where id = p_team_id
  returning * into v_team;

  return v_team;
end;
$$;

grant execute on function public.confirmar_plantilla(uuid) to authenticated;

-- Volver a abrir el armado, si el capitán quiere revisar de nuevo.
create or replace function public.reabrir_plantilla(p_team_id uuid)
returns public.teams
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_team public.teams;
begin
  if not (public.can_captain(p_team_id) or public.can_edit_team(p_team_id)) then
    raise exception 'Solo el capitán o el cuerpo técnico pueden hacer esto'
      using errcode = '42501';
  end if;

  update public.teams set plantilla_confirmada = false
  where id = p_team_id returning * into v_team;

  return v_team;
end;
$$;

grant execute on function public.reabrir_plantilla(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- Avisos: bloqueos siempre, composición solo mientras se arma
-- ---------------------------------------------------------------------
create or replace function public.avisos_de_plantilla(p_team_id uuid)
returns table (
  tipo     text,     -- 'bloqueo' | 'aviso'
  mensaje  text
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_total     int;
  v_con_ced   int;
  v_porteros  int;
  v_confirmada boolean;
  r           record;
begin
  select plantilla_confirmada into v_confirmada
  from public.teams where id = p_team_id;

  select count(*) filter (where is_active),
         count(*) filter (where is_active and cedula is not null),
         count(*) filter (where is_active and position = 'GK')
    into v_total, v_con_ced, v_porteros
  from public.players where team_id = p_team_id;

  -- Esto impide jugar, así que se dice siempre.
  if v_con_ced < 11 then
    return query select 'bloqueo'::text,
      format('Faltan %s jugadores con cédula para completar los 11 obligatorios.',
             11 - v_con_ced);
  end if;

  if v_total > v_con_ced then
    return query select 'aviso'::text,
      format('%s jugador(es) sin cédula: no cuentan para los 11.',
             v_total - v_con_ced);
  end if;

  -- De aquí para abajo, solo mientras el capitán arma el equipo.
  if coalesce(v_confirmada, false) then
    return;
  end if;

  if v_porteros = 0 then
    return query select 'aviso'::text, 'No hay ningún portero en la plantilla.';
  elsif v_porteros > 1 then
    return query select 'aviso'::text,
      format('Hay %s porteros. Normalmente juega uno.', v_porteros);
  end if;

  for r in
    select position_detail, count(*) n
    from public.players
    where team_id = p_team_id and is_active and position_detail is not null
    group by position_detail having count(*) > 1
  loop
    return query select 'aviso'::text,
      format('%s jugadores puestos como "%s".', r.n, r.position_detail);
  end loop;

  return;
end;
$$;

grant execute on function public.avisos_de_plantilla(uuid) to authenticated;

-- La vista de estado lleva la marca, para que la app sepa si ofrecer el
-- botón de confirmar.
drop view if exists public.estado_plantilla;
create view public.estado_plantilla
with (security_invoker = true)
as
select
  t.id                                   as team_id,
  t.name                                 as equipo,
  t.group_id,
  t.plantilla_confirmada,
  count(p.*) filter (where p.is_active)                          as jugadores,
  count(p.*) filter (where p.is_active and p.cedula is not null) as con_cedula,
  count(p.*) filter (where p.is_active and p.user_id is not null) as ya_registrados,
  greatest(0, 11 - count(p.*) filter (where p.is_active and p.cedula is not null))
                                                                 as faltan,
  public.equipo_habilitado(t.id)                                 as habilitado
from public.teams t
left join public.players p on p.team_id = t.id
group by t.id, t.name, t.group_id, t.plantilla_confirmada;

grant select on public.estado_plantilla to authenticated;


-- #####################################################################
-- # 20260824070000_25_un_equipo_por_grupo_solo_jugadores.sql
-- #####################################################################

-- =====================================================================
-- Anotar Gol - 25 | La regla de un equipo por grupo es para JUGADORES
-- =====================================================================
-- La migración 22 bloqueaba cualquier segunda membresía en un mismo
-- grupo. Al probarlo salió el problema: el dev creando tres equipos en
-- una liga queda como owner de cada uno y choca consigo mismo:
--
--   ERROR: Ya perteneces a Halcones A en este grupo
--
-- Además contradecía a `groups.max_equipos_por_miembro`, que permite
-- fundar más de un equipo en el mismo grupo. Dos reglas peleándose.
--
-- La regla pedida es sobre quien JUEGA: "un jugador jamás en dos equipos
-- del mismo grupo", porque se enfrentarían y no se sabría de qué lado
-- juega. Administrar dos clubes de una liga no es jugar en los dos.
--
-- Queda así:
--   * Ficha de jugador (`players`, por cédula) -> una por grupo, estricto.
--     Es la identidad en la cancha.
--   * Membresía con rol 'player' -> una por grupo.
--   * Roles de gestión (owner, admin, coach) y el dev -> sin tope.
-- =====================================================================

create or replace function public.una_membresia_por_grupo()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_grupo  uuid;
  v_choque text;
begin
  -- Solo la membresía de quien juega. Dirigir o entrenar dos clubes de
  -- una misma liga es raro, pero no rompe nada en la cancha.
  if new.role <> 'player' then
    return new;
  end if;

  if public.es_dev() then
    return new;
  end if;

  select group_id into v_grupo from public.teams where id = new.team_id;
  if v_grupo is null then
    return new;
  end if;

  select t.name into v_choque
  from public.team_members tm
  join public.teams t on t.id = tm.team_id
  where tm.user_id = new.user_id
    and tm.team_id <> new.team_id
    and tm.role = 'player'
    and t.group_id = v_grupo
  limit 1;

  if v_choque is not null then
    raise exception 'Ya juegas en % dentro de este grupo', v_choque
      using errcode = '23505',
            hint = 'Puedes jugar en varias ligas, pero solo en un equipo de cada una.';
  end if;

  return new;
end;
$$;

-- La ficha por cédula sí es estricta: exime solo lo que no tiene grupo.
-- (Sin cambios respecto de la migración 22; se deja el comentario para
-- que quede claro que la asimetría es deliberada.)
comment on function public.un_equipo_por_grupo is
  'Una cédula, un equipo por grupo. Es la identidad en la cancha: estricto a propósito.';


-- #####################################################################
-- # 20260824080000_26_el_dev_es_invisible.sql
-- #####################################################################

-- =====================================================================
-- Anotar Gol - 26 | El dev no pertenece a nada y nadie sabe que está
-- =====================================================================
-- Aclaración del 24/08/2026:
--
--   El dev NO es parte de ningún equipo ni de ningún grupo. Solo mantiene
--   la app. Tiene acceso a la información de todos, pero nadie lo sabe.
--
-- Qué estaba mal:
--   `crear_grupo` metía al dev en `group_members` como administrador del
--   grupo. Es decir: aparecía en la lista de miembros de cada liga que
--   creaba. Cualquiera podía verlo.
--
-- Cómo queda:
--   * El dev crea el grupo pero NO entra en él. El grupo nace sin
--     miembros y con una clave de ADMINISTRADOR: quien la canjea se
--     convierte en el administrador real de esa liga.
--   * El dev tampoco funda equipos. Si lo hiciera, el trigger lo pondría
--     como dueño y capitán, y volvería a aparecer en una plantilla.
--   * Su poder no viene de pertenecer: viene de `es_dev()`, que ya está
--     dentro de todas las funciones de permisos. Ve todo sin figurar en
--     ninguna lista.
--
-- Sobre "nadie lo sabe": `app_admins` solo la lee un dev, y su perfil no
-- es visible para nadie porque `profiles_select` exige compartir equipo
-- o grupo, y el dev no comparte ninguno. Lo único que queda es el uuid
-- en `groups.created_by`, que sin perfil legible no dice nada.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Tercer tipo de clave: la de administrador del grupo
-- ---------------------------------------------------------------------
alter table public.group_invites
  add column if not exists para_admin boolean not null default false;

comment on column public.group_invites.para_admin is
  'true = quien la canjee queda como administrador de la liga. La usa el dev al crearla.';

create or replace function public.crear_invitacion(
  p_group_id     uuid,
  p_max_usos     int     default null,
  p_dias         int     default null,
  p_para_capitan boolean default false,
  p_para_admin   boolean default false
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

  -- Repartir el mando de la liga es cosa del dev o de quien ya la manda.
  if p_para_admin and not (public.es_dev() or public.es_admin_del_grupo(p_group_id)) then
    raise exception 'No puedes crear claves de administrador' using errcode = '42501';
  end if;

  insert into public.group_invites (
    group_id, code, created_by, max_uses, expires_at, para_capitan, para_admin
  )
  values (
    p_group_id,
    public.generar_codigo_invitacion(),
    auth.uid(),
    p_max_usos,
    case when p_dias is null then null else now() + make_interval(days => p_dias) end,
    coalesce(p_para_capitan, false) or coalesce(p_para_admin, false),
    coalesce(p_para_admin, false)
  )
  returning * into v_inv;

  return v_inv;
end;
$$;

drop function if exists public.crear_invitacion(uuid, int, int, boolean);

grant execute on function public.crear_invitacion(uuid, int, int, boolean, boolean)
  to authenticated;

-- ---------------------------------------------------------------------
-- 2. Canjear una clave de administrador
-- ---------------------------------------------------------------------
create or replace function public.unirse_con_codigo(p_codigo text)
returns public.groups
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_inv   public.group_invites;
  v_grupo public.groups;
  v_rol   public.group_role;
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

  v_rol := case when v_inv.para_admin then 'group_admin' else 'member' end
             ::public.group_role;

  if exists (
    select 1 from public.group_members
    where group_id = v_inv.group_id and user_id = auth.uid()
  ) then
    -- Ya estabas dentro: la clave solo puede subir permisos, nunca
    -- bajarlos, para que canjear una de jugador no degrade a un admin.
    if v_inv.para_capitan or v_inv.para_admin then
      update public.group_members
      set puede_fundar_equipo = puede_fundar_equipo or v_inv.para_capitan or v_inv.para_admin,
          role = case when v_inv.para_admin then 'group_admin'::public.group_role else role end
      where group_id = v_inv.group_id and user_id = auth.uid();
      update public.group_invites set uses = uses + 1 where id = v_inv.id;
    end if;
    return v_grupo;
  end if;

  insert into public.group_members (group_id, user_id, role, puede_fundar_equipo)
  values (v_inv.group_id, auth.uid(), v_rol,
          v_inv.para_capitan or v_inv.para_admin);

  update public.group_invites set uses = uses + 1 where id = v_inv.id;

  return v_grupo;
end;
$$;

grant execute on function public.unirse_con_codigo(text) to authenticated;

-- ---------------------------------------------------------------------
-- 3. El dev crea el grupo pero no entra
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

  if not public.es_dev() then
    raise exception 'Solo la cuenta de desarrollo puede crear grupos'
      using errcode = '42501',
            hint = 'Pide una clave de invitación a quien administra el grupo.';
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

  -- El dev NO se agrega como miembro: no pertenece a la liga y no debe
  -- figurar en su lista de integrantes.
  --
  -- El grupo nace con una clave de ADMINISTRADOR. Quien la canjee será
  -- el administrador real, y desde ahí reparte las de capitán y jugador.
  insert into public.group_invites (group_id, code, created_by, para_capitan, para_admin)
  values (v_grupo.id, public.generar_codigo_invitacion(), auth.uid(), true, true);

  return v_grupo;
end;
$$;

grant execute on function public.crear_grupo(text, text) to authenticated;

-- ---------------------------------------------------------------------
-- 4. El dev tampoco funda equipos
-- ---------------------------------------------------------------------
-- Si lo hiciera, `handle_new_team` lo pondría de dueño y capitán, y
-- volvería a aparecer en una plantilla.
create or replace function public.handle_new_team()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_es_dev boolean := false;
begin
  if new.created_by is not null then
    select exists (select 1 from public.app_admins a where a.user_id = new.created_by)
      into v_es_dev;
  end if;

  -- El dev no entra a ninguna plantilla, ni siquiera a una que él cree.
  if new.created_by is not null and not v_es_dev then
    insert into public.team_members (team_id, user_id, role, is_captain)
    values (new.id, new.created_by, 'owner', true)
    on conflict (team_id, user_id) do update
      set role = 'owner', is_captain = true;
  end if;

  insert into public.team_settings (team_id)
  values (new.id)
  on conflict (team_id) do nothing;

  return new;
end;
$$;

-- Y se le dice claramente, en vez de dejarle crear equipos huérfanos.
create or replace function public.create_team(
  p_name            text,
  p_short_name      text default null,
  p_primary_color   text default '#1B5E20',
  p_secondary_color text default '#FFD700',
  p_is_public       boolean default false,
  p_group_id        uuid default null
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
    raise exception 'Debes iniciar sesión para crear un equipo'
      using errcode = '42501';
  end if;

  if public.es_dev() then
    raise exception 'La cuenta de desarrollo no funda equipos'
      using errcode = '42501',
            hint = 'Entrega una clave de capitán para que el club lo cree.';
  end if;

  if p_group_id is not null then
    if not public.es_miembro_del_grupo(p_group_id) then
      raise exception 'No perteneces a ese grupo'
        using errcode = '42501',
              hint = 'Únete al grupo con su clave de invitación antes de crear el equipo.';
    end if;

    if not public.puedo_crear_equipo(p_group_id) then
      raise exception 'Necesitas una clave de capitán para fundar un equipo en este grupo'
        using errcode = '42501',
              hint = 'Pídesela a quien administra el grupo.';
    end if;
  end if;

  v_base_slug := coalesce(nullif(public.slugify(p_name), ''), 'equipo');
  v_slug := v_base_slug;

  while exists (select 1 from public.teams t where t.slug = v_slug) loop
    v_suffix := v_suffix + 1;
    v_slug := v_base_slug || '-' || v_suffix;
  end loop;

  insert into public.teams (
    name, short_name, slug, primary_color, secondary_color,
    is_public, group_id, created_by
  )
  values (
    btrim(p_name), nullif(btrim(coalesce(p_short_name, '')), ''), v_slug,
    p_primary_color, p_secondary_color, p_is_public, p_group_id, auth.uid()
  )
  returning * into v_team;

  return v_team;
end;
$$;

grant execute on function public.create_team(text, text, text, text, boolean, uuid)
  to authenticated;


-- #####################################################################
-- # 20260824090000_27_dev_sin_rastro.sql
-- #####################################################################

-- =====================================================================
-- Anotar Gol - 27 | Que el dev no deje rastro
-- =====================================================================
-- La migración 26 sacó al dev de las listas de miembros. Faltaba una
-- fuga más fina:
--
--   `groups.created_by` y `group_invites.created_by` guardaban su uuid,
--   y el administrador de la liga puede leer esas tablas. Vería un
--   identificador que no aparece en ningún listado de miembros y del que
--   no puede leer el perfil. De ahí a deducir "hay alguien más con
--   acceso" hay un paso.
--
-- Solución: en las columnas visibles no se guarda nada, y la trazabilidad
-- se mueve a una bitácora que solo el dev puede leer. No se pierde el
-- registro de quién hizo qué; deja de estar a la vista.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Bitácora privada
-- ---------------------------------------------------------------------
create table if not exists public.dev_audit (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users (id) on delete set null,
  accion      text not null,
  tabla       text,
  registro_id uuid,
  detalle     jsonb,
  created_at  timestamptz not null default now()
);

create index if not exists dev_audit_fecha_idx on public.dev_audit (created_at desc);

alter table public.dev_audit enable row level security;

drop policy if exists dev_audit_solo_dev on public.dev_audit;
create policy dev_audit_solo_dev on public.dev_audit
  for all to authenticated
  using (public.es_dev())
  with check (public.es_dev());

comment on table public.dev_audit is
  'Qué hizo la cuenta de desarrollo. Solo la lee un dev: mantiene la trazabilidad sin exponerla.';

create or replace function public.registrar_accion_dev(
  p_accion      text,
  p_tabla       text default null,
  p_registro_id uuid default null,
  p_detalle     jsonb default null
)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  insert into public.dev_audit (user_id, accion, tabla, registro_id, detalle)
  values (auth.uid(), p_accion, p_tabla, p_registro_id, p_detalle);
$$;

-- ---------------------------------------------------------------------
-- 2. Crear grupo sin firmar
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
  v_code  text;
begin
  if auth.uid() is null then
    raise exception 'Debes iniciar sesión' using errcode = '42501';
  end if;

  if not public.es_dev() then
    raise exception 'Solo la cuenta de desarrollo puede crear grupos'
      using errcode = '42501',
            hint = 'Pide una clave de invitación a quien administra el grupo.';
  end if;

  v_base := coalesce(nullif(public.slugify(p_nombre), ''), 'grupo');
  v_slug := v_base;
  while exists (select 1 from public.groups g where g.slug = v_slug) loop
    v_n := v_n + 1;
    v_slug := v_base || '-' || v_n;
  end loop;

  -- created_by queda en null: el dev no firma lo que crea. Quien mire la
  -- fila ve una liga sin autor, no una liga creada por un desconocido.
  insert into public.groups (name, slug, description, created_by)
  values (btrim(p_nombre), v_slug, p_descripcion, null)
  returning * into v_grupo;

  v_code := public.generar_codigo_invitacion();

  insert into public.group_invites (
    group_id, code, created_by, para_capitan, para_admin
  )
  values (v_grupo.id, v_code, null, true, true);

  perform public.registrar_accion_dev(
    'crear_grupo', 'groups', v_grupo.id,
    jsonb_build_object('nombre', v_grupo.name, 'clave_admin', v_code));

  return v_grupo;
end;
$$;

grant execute on function public.crear_grupo(text, text) to authenticated;

-- ---------------------------------------------------------------------
-- 3. Las invitaciones del dev tampoco llevan firma
-- ---------------------------------------------------------------------
create or replace function public.crear_invitacion(
  p_group_id     uuid,
  p_max_usos     int     default null,
  p_dias         int     default null,
  p_para_capitan boolean default false,
  p_para_admin   boolean default false
)
returns public.group_invites
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_inv    public.group_invites;
  v_es_dev boolean := public.es_dev();
begin
  if not public.es_admin_del_grupo(p_group_id) then
    raise exception 'Solo un administrador del grupo puede crear invitaciones'
      using errcode = '42501';
  end if;

  if p_para_admin and not (v_es_dev or public.es_admin_del_grupo(p_group_id)) then
    raise exception 'No puedes crear claves de administrador' using errcode = '42501';
  end if;

  insert into public.group_invites (
    group_id, code, created_by, max_uses, expires_at, para_capitan, para_admin
  )
  values (
    p_group_id,
    public.generar_codigo_invitacion(),
    case when v_es_dev then null else auth.uid() end,
    p_max_usos,
    case when p_dias is null then null else now() + make_interval(days => p_dias) end,
    coalesce(p_para_capitan, false) or coalesce(p_para_admin, false),
    coalesce(p_para_admin, false)
  )
  returning * into v_inv;

  if v_es_dev then
    perform public.registrar_accion_dev(
      'crear_invitacion', 'group_invites', v_inv.id,
      jsonb_build_object('grupo', p_group_id, 'para_admin', p_para_admin));
  end if;

  return v_inv;
end;
$$;

grant execute on function public.crear_invitacion(uuid, int, int, boolean, boolean)
  to authenticated;

-- ---------------------------------------------------------------------
-- 4. Limpiar el rastro que ya existiera
-- ---------------------------------------------------------------------
update public.groups
set created_by = null
where created_by in (select user_id from public.app_admins);

update public.group_invites
set created_by = null
where created_by in (select user_id from public.app_admins);

update public.teams
set created_by = null
where created_by in (select user_id from public.app_admins);


-- #####################################################################
-- # 20260824100000_28_el_dev_es_un_dios.sql
-- #####################################################################

-- =====================================================================
-- Anotar Gol - 28 | Poder total para el dev, y sin dejar rastro
-- =====================================================================
-- Al probar qué podía hacer realmente el dev dentro de un equipo ajeno
-- salieron tres cosas que no cuadraban con "puede hacer lo que quiera y
-- nadie lo ve":
--
--   1. FUGA: anotar un gol dejaba su uuid en `match_events.created_by`,
--      que el capitán y el administrador de liga pueden leer. Verían un
--      autor desconocido en un gol que nadie del club registró.
--
--   2. NO PODÍA cambiar una cédula: el trigger de la migración 21 se la
--      bloquea a todo el mundo. Para un mantenedor que tiene que
--      corregir un dato mal cargado, eso es una traba.
--
--   3. NO PODÍA borrar equipos: `teams_delete` exige ser owner del club
--      y nunca se le agregó. Podía borrar ligas enteras pero no un solo
--      equipo.
--
-- Se arreglan las tres. La única cosa que se le sigue negando es
-- escribir en los chats, y es a propósito: un mensaje suyo aparecería en
-- pantalla firmado por un usuario que nadie conoce. Es la acción que
-- rompe la invisibilidad por definición, no por una regla que se pueda
-- levantar.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. El dev no firma nada, en ninguna tabla
-- ---------------------------------------------------------------------
-- Se resuelve con un trigger genérico en vez de parchear cada RPC: así
-- cubre también los caminos que se agreguen después.
create or replace function public.borrar_firma_del_dev()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.created_by is not null
     and exists (select 1 from public.app_admins a where a.user_id = new.created_by) then
    new.created_by := null;
  end if;
  return new;
end;
$$;

comment on function public.borrar_firma_del_dev is
  'Deja en null el created_by cuando quien actúa es la cuenta de desarrollo.';

do $$
declare
  t text;
begin
  for t in
    select c.table_name
    from information_schema.columns c
    join information_schema.tables tb
      on tb.table_schema = c.table_schema and tb.table_name = c.table_name
    where c.table_schema = 'public'
      and c.column_name = 'created_by'
      and tb.table_type = 'BASE TABLE'
  loop
    execute format('drop trigger if exists sin_firma_del_dev on public.%I', t);
    execute format(
      'create trigger sin_firma_del_dev before insert or update on public.%I
       for each row execute function public.borrar_firma_del_dev()', t);
  end loop;
end
$$;

-- Y se limpia lo que ya estuviera firmado.
do $$
declare
  t text;
begin
  for t in
    select c.table_name
    from information_schema.columns c
    join information_schema.tables tb
      on tb.table_schema = c.table_schema and tb.table_name = c.table_name
    where c.table_schema = 'public'
      and c.column_name = 'created_by'
      and tb.table_type = 'BASE TABLE'
  loop
    execute format(
      'update public.%I set created_by = null
       where created_by in (select user_id from public.app_admins)', t);
  end loop;
end
$$;

-- ---------------------------------------------------------------------
-- 2. El dev sí puede corregir una cédula
-- ---------------------------------------------------------------------
create or replace function public.proteger_cedula_jugador()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_reclama_su_ficha boolean;
begin
  if old.cedula is not null and new.cedula is distinct from old.cedula then
    -- El mantenedor tiene que poder arreglar un dato mal cargado. Queda
    -- anotado en la bitácora privada, que solo él lee.
    if public.es_dev() then
      perform public.registrar_accion_dev(
        'cambiar_cedula', 'players', old.id,
        jsonb_build_object('antes', old.cedula, 'despues', new.cedula));
    else
      raise exception 'La cédula no se puede cambiar: es la identidad del jugador'
        using errcode = '42501',
              hint = 'Si te equivocaste, saca la ficha y créala de nuevo con la cédula correcta.';
    end if;
  end if;

  v_reclama_su_ficha :=
       old.user_id is null
   and new.user_id is not null
   and old.cedula is not null
   and exists (
         select 1 from public.profiles pr
         where pr.id = new.user_id and pr.cedula = old.cedula);

  if not public.can_edit_squad(old.team_id) and not v_reclama_su_ficha then
    if new.team_id is distinct from old.team_id
       or new.user_id is distinct from old.user_id
       or new.is_active is distinct from old.is_active then
      raise exception 'Solo puedes cambiar tu nombre, tu dorsal y tu posición'
        using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

-- La regla de un equipo por grupo tampoco lo frena: si tiene que mover a
-- alguien para arreglar un enredo, puede.
create or replace function public.un_equipo_por_grupo()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_grupo  uuid;
  v_choque text;
begin
  if new.cedula is null or not new.is_active or public.es_dev() then
    return new;
  end if;

  select group_id into v_grupo from public.teams where id = new.team_id;
  if v_grupo is null then
    return new;
  end if;

  select t.name into v_choque
  from public.players p
  join public.teams t on t.id = p.team_id
  where p.cedula = new.cedula
    and p.is_active
    and p.id is distinct from new.id
    and t.group_id = v_grupo
  limit 1;

  if v_choque is not null then
    raise exception 'Esa cédula ya juega en % dentro de este mismo grupo', v_choque
      using errcode = '23505',
            hint = 'Una persona puede estar en varios grupos, pero solo en un equipo de cada uno.';
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. Borrar equipos enteros
-- ---------------------------------------------------------------------
drop policy if exists teams_delete on public.teams;
create policy teams_delete on public.teams
  for delete to authenticated
  using (public.es_dev() or public.team_role_of(id) = 'owner');

-- Y que el guardián del último owner no le estorbe.
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
  if public.es_dev() then
    return coalesce(new, old);
  end if;

  if old.role <> 'owner' then
    return coalesce(new, old);
  end if;

  if tg_op = 'UPDATE' and new.role = 'owner' then
    return new;
  end if;

  if not exists (select 1 from public.teams where id = v_team_id) then
    return coalesce(new, old);
  end if;

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

-- ---------------------------------------------------------------------
-- 4. Borrado con bitácora
-- ---------------------------------------------------------------------
-- Borrar una liga se lleva por delante equipos, jugadores, partidos e
-- historial. Que no quede rastro para los usuarios no significa que no
-- quede rastro para él.
create or replace function public.dev_borrar_grupo(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_nombre  text;
  v_equipos int;
begin
  if not public.es_dev() then
    raise exception 'Solo la cuenta de desarrollo' using errcode = '42501';
  end if;

  select name into v_nombre from public.groups where id = p_group_id;
  if v_nombre is null then
    raise exception 'Ese grupo no existe' using errcode = 'P0002';
  end if;

  select count(*) into v_equipos from public.teams where group_id = p_group_id;

  perform public.registrar_accion_dev(
    'borrar_grupo', 'groups', p_group_id,
    jsonb_build_object('nombre', v_nombre, 'equipos_arrastrados', v_equipos));

  delete from public.groups where id = p_group_id;
end;
$$;

create or replace function public.dev_borrar_equipo(p_team_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_nombre text;
  v_jug    int;
begin
  if not public.es_dev() then
    raise exception 'Solo la cuenta de desarrollo' using errcode = '42501';
  end if;

  select name into v_nombre from public.teams where id = p_team_id;
  if v_nombre is null then
    raise exception 'Ese equipo no existe' using errcode = 'P0002';
  end if;

  select count(*) into v_jug from public.players where team_id = p_team_id;

  perform public.registrar_accion_dev(
    'borrar_equipo', 'teams', p_team_id,
    jsonb_build_object('nombre', v_nombre, 'jugadores', v_jug));

  delete from public.teams where id = p_team_id;
end;
$$;

grant execute on function public.dev_borrar_grupo(uuid)  to authenticated;
grant execute on function public.dev_borrar_equipo(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 5. Lo único que no puede: hablar
-- ---------------------------------------------------------------------
-- Escribir en un chat es visible por definición: el mensaje aparecería
-- firmado por alguien que nadie conoce. Leer sí puede, para moderar.
comment on policy team_messages_insert on public.team_messages is
  'El dev no escribe en los chats: un mensaje suyo rompería su invisibilidad.';


-- #####################################################################
-- # 20260824110000_29_reloj_del_partido.sql
-- #####################################################################

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


-- #####################################################################
-- # 20260824120000_30_revisar_clave.sql
-- #####################################################################

-- =====================================================================
-- Anotar Gol - 30 | Saber qué es una clave antes de canjearla
-- =====================================================================
-- El flujo de entrada es: cédula + clave de invitación, y el sistema
-- decide solo qué hacer con esa clave. Pero `canjear_clave()` la consume
-- y recién ahí uno se entera de qué era.
--
-- Eso está mal para quien la escribe: tiene que ver ANTES qué le va a
-- pasar. No es lo mismo "esta clave te hace capitán de la Liga Norte y
-- vas a poder fundar tu equipo" que "esta clave te suma a Halcones FC
-- como jugador".
--
-- `revisar_clave()` lo dice sin gastar un uso.
--
-- Sobre exponer el nombre de la liga a quien tiene el código: el código
-- son 8 caracteres de un alfabeto de 32, o sea del orden de 10^12
-- combinaciones. Adivinarlo no es una vía practicable, y quien lo tiene
-- es porque alguien se lo dio.
-- =====================================================================

create or replace function public.revisar_clave(p_codigo text)
returns table (
  valida       boolean,
  motivo       text,     -- por qué no sirve, si no sirve
  tipo         text,     -- 'admin' | 'capitan' | 'jugador' | 'equipo'
  descripcion  text,     -- qué le va a pasar a quien la canjee
  group_id     uuid,
  grupo        text,
  team_id      uuid,
  equipo       text,
  rol_equipo   text
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_c   text := upper(btrim(coalesce(p_codigo, '')));
  gi    public.group_invites;
  ti    public.team_invites;
  v_g   public.groups;
  v_t   public.teams;
begin
  if char_length(v_c) < 4 then
    return query select false, 'La clave son 8 caracteres.'::text,
      null::text, null::text, null::uuid, null::text, null::uuid, null::text, null::text;
    return;
  end if;

  -- ¿Clave de grupo?
  select * into gi from public.group_invites where upper(btrim(code)) = v_c;

  if gi.id is not null then
    select * into v_g from public.groups where id = gi.group_id;

    if not gi.is_active then
      return query select false, 'Esa invitación fue desactivada.'::text,
        null::text, null::text, v_g.id, v_g.name, null::uuid, null::text, null::text;
      return;
    end if;
    if gi.expires_at is not null and gi.expires_at < now() then
      return query select false, 'Esa invitación ya venció.'::text,
        null::text, null::text, v_g.id, v_g.name, null::uuid, null::text, null::text;
      return;
    end if;
    if gi.max_uses is not null and gi.uses >= gi.max_uses then
      return query select false, 'Esa invitación ya se usó el máximo de veces.'::text,
        null::text, null::text, v_g.id, v_g.name, null::uuid, null::text, null::text;
      return;
    end if;

    return query select
      true,
      null::text,
      case when gi.para_admin then 'admin'
           when gi.para_capitan then 'capitan'
           else 'jugador' end,
      case when gi.para_admin then
             format('Vas a administrar la liga %s.', v_g.name)
           when gi.para_capitan then
             format('Entras a %s y podrás fundar tu equipo.', v_g.name)
           else
             format('Entras a %s. Para jugar, tu capitán tiene que ficharte.', v_g.name)
      end,
      v_g.id, v_g.name, null::uuid, null::text, null::text;
    return;
  end if;

  -- ¿Clave de equipo?
  select * into ti from public.team_invites where upper(btrim(code)) = v_c;

  if ti.id is not null then
    select * into v_t from public.teams where id = ti.team_id;
    select * into v_g from public.groups where id = v_t.group_id;

    if not ti.is_active then
      return query select false, 'Esa clave fue desactivada.'::text,
        null::text, null::text, v_g.id, v_g.name, v_t.id, v_t.name, null::text;
      return;
    end if;
    if ti.expires_at is not null and ti.expires_at < now() then
      return query select false, 'Esa clave ya venció.'::text,
        null::text, null::text, v_g.id, v_g.name, v_t.id, v_t.name, null::text;
      return;
    end if;
    if ti.max_uses is not null and ti.uses >= ti.max_uses then
      return query select false, 'Esa clave ya se usó el máximo de veces.'::text,
        null::text, null::text, v_g.id, v_g.name, v_t.id, v_t.name, null::text;
      return;
    end if;

    return query select
      true,
      null::text,
      'equipo'::text,
      format('Te sumas a %s como %s.',
             v_t.name,
             case ti.rol
               when 'player' then 'jugador'
               when 'coach'  then 'cuerpo técnico'
               else 'hincha'
             end),
      v_g.id, v_g.name, v_t.id, v_t.name, ti.rol::text;
    return;
  end if;

  return query select false, 'Esa clave no existe. Revísala con quien te la envió.'::text,
    null::text, null::text, null::uuid, null::text, null::uuid, null::text, null::text;
end;
$$;

grant execute on function public.revisar_clave(text) to anon, authenticated;

comment on function public.revisar_clave is
  'Dice qué hace una clave sin consumirla, para poder confirmarlo antes de canjear.';

-- ---------------------------------------------------------------------
-- Canjear devolviendo también qué pasó
-- ---------------------------------------------------------------------
-- La app necesita saber a dónde llevar al usuario después: a fundar su
-- equipo, o directo al equipo al que acaba de entrar.
--
-- Se suelta primero: `create or replace` no puede cambiar el tipo de
-- retorno de una función que ya existe, y esta gana una columna.
drop function if exists public.canjear_clave(text);

create or replace function public.canjear_clave(p_codigo text)
returns table (
  tipo         text,
  group_id     uuid,
  group_name   text,
  team_id      uuid,
  team_name    text,
  puede_fundar boolean
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_codigo text := upper(btrim(p_codigo));
  v_grupo  public.groups;
  v_equipo public.teams;
  v_funda  boolean := false;
begin
  if exists (select 1 from public.group_invites where upper(btrim(code)) = v_codigo) then
    v_grupo := public.unirse_con_codigo(v_codigo);

    select gm.puede_fundar_equipo into v_funda
    from public.group_members gm
    where gm.group_id = v_grupo.id and gm.user_id = auth.uid();

    return query select 'grupo'::text, v_grupo.id, v_grupo.name,
      null::uuid, null::text, coalesce(v_funda, false);
    return;
  end if;

  if exists (select 1 from public.team_invites where upper(btrim(code)) = v_codigo) then
    v_equipo := public.unirse_a_equipo_con_codigo(v_codigo);
    select * into v_grupo from public.groups where id = v_equipo.group_id;

    select gm.puede_fundar_equipo into v_funda
    from public.group_members gm
    where gm.group_id = v_equipo.group_id and gm.user_id = auth.uid();

    return query select 'equipo'::text, v_grupo.id, v_grupo.name,
      v_equipo.id, v_equipo.name, coalesce(v_funda, false);
    return;
  end if;

  raise exception 'Esa clave no existe. Revísala con quien te la envió.'
    using errcode = 'P0002';
end;
$$;

grant execute on function public.canjear_clave(text) to authenticated;

-- ---------------------------------------------------------------------
-- Dónde quedó parado el usuario
-- ---------------------------------------------------------------------
-- Después de registrarse con cédula y canjear su clave, la app necesita
-- una sola respuesta: ¿a dónde lo llevo?
create or replace function public.mi_situacion()
returns table (
  tiene_grupo     boolean,
  tiene_equipo    boolean,
  puede_fundar    boolean,
  group_id        uuid,
  grupo           text,
  team_id         uuid,
  equipo          text,
  soy_capitan     boolean,
  tengo_cedula    boolean
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with mi_ficha as (
    select tm.team_id, t.name as equipo, t.group_id, tm.is_captain
    from public.team_members tm
    join public.teams t on t.id = tm.team_id
    where tm.user_id = auth.uid()
    order by tm.created_at
    limit 1
  ),
  mi_grupo as (
    select gm.group_id, g.name, gm.puede_fundar_equipo
    from public.group_members gm
    join public.groups g on g.id = gm.group_id
    where gm.user_id = auth.uid()
    order by gm.joined_at
    limit 1
  )
  select
    (select count(*) from public.group_members where user_id = auth.uid()) > 0,
    (select count(*) from public.team_members  where user_id = auth.uid()) > 0,
    coalesce((select puede_fundar_equipo from mi_grupo), false),
    coalesce((select group_id from mi_ficha), (select group_id from mi_grupo)),
    coalesce((select g.name from public.groups g
               where g.id = (select group_id from mi_ficha)),
             (select name from mi_grupo)),
    (select team_id from mi_ficha),
    (select equipo from mi_ficha),
    coalesce((select is_captain from mi_ficha), false),
    (select cedula is not null from public.profiles where id = auth.uid());
$$;

grant execute on function public.mi_situacion() to authenticated;

comment on function public.mi_situacion is
  'Una sola respuesta para que la app sepa a qué pantalla llevar al usuario.';


-- #####################################################################
-- # 20260824130000_31_borrar_cuenta_con_ficha.sql
-- #####################################################################

-- =====================================================================
-- Anotar Gol - 31 | Borrar la cuenta cuando tienes ficha de jugador
-- =====================================================================
-- Sintoma:
--   Borrar un usuario que está fichado en un equipo falla con
--   "Solo puedes cambiar tu nombre, tu dorsal y tu posición".
--
-- Causa:
--   `players.user_id` tiene `on delete set null`. Al borrar la cuenta,
--   Postgres pone ese campo en null, y eso dispara el trigger que
--   protege la ficha. Durante el arrastre no hay sesión, así que
--   `auth.uid()` es null, `can_edit_squad` da falso, y el trigger corta.
--
-- Por qué importa:
--   Es exactamente el mismo tropiezo que ya hubo con `protect_last_owner`
--   (migración 10): una regla pensada para impedir un abuso terminó
--   bloqueando el borrado de cuenta. Y poder borrar la cuenta desde la
--   app es requisito de Google Play y de la App Store para cualquier app
--   con registro.
--
-- Arreglo:
--   Se reconoce el arrastre: si `user_id` pasa a null porque la cuenta
--   ya no existe, se deja pasar. La ficha se queda en el equipo, sin
--   dueño, y sus goles siguen en el historial.
-- =====================================================================

create or replace function public.proteger_cedula_jugador()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_reclama_su_ficha boolean;
  v_cuenta_borrada   boolean;
begin
  if old.cedula is not null and new.cedula is distinct from old.cedula then
    if public.es_dev() then
      perform public.registrar_accion_dev(
        'cambiar_cedula', 'players', old.id,
        jsonb_build_object('antes', old.cedula, 'despues', new.cedula));
    else
      raise exception 'La cédula no se puede cambiar: es la identidad del jugador'
        using errcode = '42501',
              hint = 'Si te equivocaste, saca la ficha y créala de nuevo con la cédula correcta.';
    end if;
  end if;

  -- La ficha queda libre porque su dueño borró la cuenta. No es alguien
  -- manipulando datos ajenos: es el arrastre de auth.users.
  v_cuenta_borrada :=
       old.user_id is not null
   and new.user_id is null
   and not exists (select 1 from auth.users u where u.id = old.user_id);

  if v_cuenta_borrada then
    return new;
  end if;

  -- Reclamar la ficha propia.
  v_reclama_su_ficha :=
       old.user_id is null
   and new.user_id is not null
   and old.cedula is not null
   and exists (
         select 1 from public.profiles pr
         where pr.id = new.user_id and pr.cedula = old.cedula);

  if not public.can_edit_squad(old.team_id) and not v_reclama_su_ficha then
    if new.team_id is distinct from old.team_id
       or new.user_id is distinct from old.user_id
       or new.is_active is distinct from old.is_active then
      raise exception 'Solo puedes cambiar tu nombre, tu dorsal y tu posición'
        using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- Borrar la propia cuenta desde la app
-- ---------------------------------------------------------------------
-- Las dos tiendas lo exigen, y hacerlo bien implica avisar de lo que se
-- pierde y de lo que queda: los goles anotados no se borran, porque el
-- gol ocurrió y el resultado del partido depende de él.
create or replace function public.que_pasa_si_borro_mi_cuenta()
returns table (
  equipos       bigint,
  grupos        bigint,
  fichas        bigint,
  goles         bigint,
  soy_capitan_de bigint,
  soy_owner_de  bigint
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    (select count(*) from public.team_members  where user_id = auth.uid()),
    (select count(*) from public.group_members where user_id = auth.uid()),
    (select count(*) from public.players       where user_id = auth.uid()),
    (select count(*) from public.match_events e
       join public.players p on p.id = e.player_id
      where p.user_id = auth.uid() and e.type = 'goal'),
    (select count(*) from public.team_members
      where user_id = auth.uid() and is_captain),
    (select count(*) from public.team_members
      where user_id = auth.uid() and role = 'owner');
$$;

grant execute on function public.que_pasa_si_borro_mi_cuenta() to authenticated;

comment on function public.que_pasa_si_borro_mi_cuenta is
  'Qué arrastra el borrado de cuenta, para poder decírselo antes de confirmar.';


-- #####################################################################
-- # 20260824140000_32_sin_hinchas.sql
-- #####################################################################

-- =====================================================================
-- Anotar Gol - 32 | Por ahora solo hay dev, capitanes y jugadores
-- =====================================================================
-- No existe la figura del hincha. Eso cambia dos cosas:
--
--   * Toda clave de LIGA es de capitán. La variante "entras a la liga
--     pero no fundas nada" no tiene a quién servir: si no eres capitán,
--     entras por la clave de tu equipo.
--   * En un EQUIPO se entra como jugador o como cuerpo técnico.
--     'viewer' deja de repartirse.
--
-- El valor `viewer` del enum se conserva: quitarlo es destructivo y no
-- cuesta nada dejarlo por si más adelante se abre la app a espectadores.
-- Lo que cambia es que ya no se entrega.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Las claves de liga son de capitán
-- ---------------------------------------------------------------------
create or replace function public.crear_invitacion(
  p_group_id     uuid,
  p_max_usos     int     default null,
  p_dias         int     default null,
  p_para_capitan boolean default true,
  p_para_admin   boolean default false
)
returns public.group_invites
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_inv    public.group_invites;
  v_es_dev boolean := public.es_dev();
begin
  if not public.es_admin_del_grupo(p_group_id) then
    raise exception 'Solo un administrador del grupo puede crear invitaciones'
      using errcode = '42501';
  end if;

  if p_para_admin and not (v_es_dev or public.es_admin_del_grupo(p_group_id)) then
    raise exception 'No puedes crear claves de administrador' using errcode = '42501';
  end if;

  -- Sin hinchas, una clave de liga que no habilite a fundar equipo no le
  -- serviría a nadie: quien no es capitán entra por la de su equipo.
  if not coalesce(p_para_capitan, true) and not coalesce(p_para_admin, false) then
    raise exception 'Las claves de liga son para capitanes'
      using errcode = '23514',
            hint = 'Un jugador entra con la clave de su equipo, no con la de la liga.';
  end if;

  insert into public.group_invites (
    group_id, code, created_by, max_uses, expires_at, para_capitan, para_admin
  )
  values (
    p_group_id,
    public.generar_codigo_invitacion(),
    case when v_es_dev then null else auth.uid() end,
    p_max_usos,
    case when p_dias is null then null else now() + make_interval(days => p_dias) end,
    true,
    coalesce(p_para_admin, false)
  )
  returning * into v_inv;

  if v_es_dev then
    perform public.registrar_accion_dev(
      'crear_invitacion', 'group_invites', v_inv.id,
      jsonb_build_object('grupo', p_group_id, 'para_admin', p_para_admin));
  end if;

  return v_inv;
end;
$$;

grant execute on function public.crear_invitacion(uuid, int, int, boolean, boolean)
  to authenticated;

-- ---------------------------------------------------------------------
-- 2. En un equipo se entra a jugar o a dirigir
-- ---------------------------------------------------------------------
create or replace function public.crear_invitacion_equipo(
  p_team_id  uuid,
  p_rol      public.team_role default 'player',
  p_max_usos int default null,
  p_dias     int default null
)
returns public.team_invites
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_inv public.team_invites;
begin
  if not (public.can_captain(p_team_id) or public.can_admin_team(p_team_id)) then
    raise exception 'Solo el capitán o un administrador del club pueden crear claves'
      using errcode = '42501';
  end if;

  if p_rol not in ('player', 'coach') then
    raise exception 'Por código se entra como jugador o como cuerpo técnico'
      using errcode = '23514',
            hint = 'Los roles de mando se otorgan a mano desde la gestión del club.';
  end if;

  insert into public.team_invites (
    team_id, code, rol, created_by, max_uses, expires_at
  )
  values (
    p_team_id,
    public.generar_codigo_invitacion(),
    p_rol,
    auth.uid(),
    p_max_usos,
    case when p_dias is null then null else now() + make_interval(days => p_dias) end
  )
  returning * into v_inv;

  return v_inv;
end;
$$;

grant execute on function public.crear_invitacion_equipo(uuid, public.team_role, int, int)
  to authenticated;

-- ---------------------------------------------------------------------
-- 3. Los textos que ve quien escribe la clave
-- ---------------------------------------------------------------------
create or replace function public.revisar_clave(p_codigo text)
returns table (
  valida       boolean,
  motivo       text,
  tipo         text,
  descripcion  text,
  group_id     uuid,
  grupo        text,
  team_id      uuid,
  equipo       text,
  rol_equipo   text
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_c text := upper(btrim(coalesce(p_codigo, '')));
  gi  public.group_invites;
  ti  public.team_invites;
  v_g public.groups;
  v_t public.teams;
begin
  if char_length(v_c) < 4 then
    return query select false, 'La clave son 8 caracteres.'::text,
      null::text, null::text, null::uuid, null::text, null::uuid, null::text, null::text;
    return;
  end if;

  select * into gi from public.group_invites where upper(btrim(code)) = v_c;

  if gi.id is not null then
    select * into v_g from public.groups where id = gi.group_id;

    if not gi.is_active then
      return query select false, 'Esa invitación fue desactivada.'::text,
        null::text, null::text, v_g.id, v_g.name, null::uuid, null::text, null::text;
      return;
    end if;
    if gi.expires_at is not null and gi.expires_at < now() then
      return query select false, 'Esa invitación ya venció.'::text,
        null::text, null::text, v_g.id, v_g.name, null::uuid, null::text, null::text;
      return;
    end if;
    if gi.max_uses is not null and gi.uses >= gi.max_uses then
      return query select false, 'Esa invitación ya se usó el máximo de veces.'::text,
        null::text, null::text, v_g.id, v_g.name, null::uuid, null::text, null::text;
      return;
    end if;

    return query select
      true,
      null::text,
      case when gi.para_admin then 'admin' else 'capitan' end,
      case when gi.para_admin then
             format('Vas a administrar la liga %s.', v_g.name)
           else
             format('Entras a %s como capitán y podrás fundar tu equipo.', v_g.name)
      end,
      v_g.id, v_g.name, null::uuid, null::text, null::text;
    return;
  end if;

  select * into ti from public.team_invites where upper(btrim(code)) = v_c;

  if ti.id is not null then
    select * into v_t from public.teams where id = ti.team_id;
    select * into v_g from public.groups where id = v_t.group_id;

    if not ti.is_active then
      return query select false, 'Esa clave fue desactivada.'::text,
        null::text, null::text, v_g.id, v_g.name, v_t.id, v_t.name, null::text;
      return;
    end if;
    if ti.expires_at is not null and ti.expires_at < now() then
      return query select false, 'Esa clave ya venció.'::text,
        null::text, null::text, v_g.id, v_g.name, v_t.id, v_t.name, null::text;
      return;
    end if;
    if ti.max_uses is not null and ti.uses >= ti.max_uses then
      return query select false, 'Esa clave ya se usó el máximo de veces.'::text,
        null::text, null::text, v_g.id, v_g.name, v_t.id, v_t.name, null::text;
      return;
    end if;

    return query select
      true,
      null::text,
      'equipo'::text,
      format('Te sumas a %s como %s.',
             v_t.name,
             case ti.rol when 'coach' then 'cuerpo técnico' else 'jugador' end),
      v_g.id, v_g.name, v_t.id, v_t.name, ti.rol::text;
    return;
  end if;

  return query select false, 'Esa clave no existe. Revísala con quien te la envió.'::text,
    null::text, null::text, null::uuid, null::text, null::uuid, null::text, null::text;
end;
$$;

grant execute on function public.revisar_clave(text) to anon, authenticated;

