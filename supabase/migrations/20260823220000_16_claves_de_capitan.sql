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
