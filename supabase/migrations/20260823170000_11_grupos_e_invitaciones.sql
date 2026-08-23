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
