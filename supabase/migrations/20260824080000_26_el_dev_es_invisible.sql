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
