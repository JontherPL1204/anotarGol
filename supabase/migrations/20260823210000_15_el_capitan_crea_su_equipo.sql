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
