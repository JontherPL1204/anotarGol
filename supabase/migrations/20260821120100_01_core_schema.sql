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
