-- =====================================================================
-- Anotar Gol - 34 | El nombre de la liga es del dev
-- =====================================================================
-- Requisito del 24/08/2026:
--
--   * Solo el dev puede cambiar el nombre de una liga.
--   * Por defecto la liga se llama "La Liga A", y las siguientes B, C...
--
-- Por qué un trigger y no solo la política de RLS:
--   RLS decide sobre la fila entera, no sobre una columna. El
--   administrador de una liga sí tiene motivos para editar su grupo (por
--   ejemplo, cuántos equipos puede fundar cada miembro), pero no su
--   identidad. Se deja pasar el update y se protegen `name` y `slug`.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Nombre por defecto: La Liga A, B, C...
-- ---------------------------------------------------------------------
-- Después de la Z sigue AA, AB... Es la misma cuenta de las columnas de
-- una hoja de cálculo, para no quedarse sin nombres a la liga 27.
create or replace function public.letra_de_liga(p_n int)
returns text
language plpgsql
immutable
as $$
declare
  v_n     int := greatest(1, p_n);
  v_letra text := '';
  v_resto int;
begin
  while v_n > 0 loop
    v_resto := (v_n - 1) % 26;
    v_letra := chr(65 + v_resto) || v_letra;
    v_n := (v_n - 1 - v_resto) / 26;
  end loop;
  return v_letra;
end;
$$;

create or replace function public.siguiente_nombre_de_liga()
returns text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_n      int := (select count(*) from public.groups) + 1;
  v_nombre text;
begin
  loop
    v_nombre := 'La Liga ' || public.letra_de_liga(v_n);
    exit when not exists (select 1 from public.groups g where g.name = v_nombre);
    v_n := v_n + 1;
  end loop;
  return v_nombre;
end;
$$;

-- ---------------------------------------------------------------------
-- 2. Crear la liga sin tener que ponerle nombre
-- ---------------------------------------------------------------------
create or replace function public.crear_grupo(
  p_nombre      text default null,
  p_descripcion text default null
)
returns public.groups
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_grupo  public.groups;
  v_nombre text;
  v_base   text;
  v_slug   text;
  v_n      int := 0;
  v_code   text;
begin
  if auth.uid() is null then
    raise exception 'Debes iniciar sesión' using errcode = '42501';
  end if;

  if not public.es_dev() then
    raise exception 'Solo la cuenta de desarrollo puede crear grupos'
      using errcode = '42501',
            hint = 'Pide una clave de invitación a quien administra el grupo.';
  end if;

  v_nombre := nullif(btrim(coalesce(p_nombre, '')), '');
  if v_nombre is null then
    v_nombre := public.siguiente_nombre_de_liga();
  end if;

  v_base := coalesce(nullif(public.slugify(v_nombre), ''), 'liga');
  v_slug := v_base;
  while exists (select 1 from public.groups g where g.slug = v_slug) loop
    v_n := v_n + 1;
    v_slug := v_base || '-' || v_n;
  end loop;

  -- El dev no firma lo que crea.
  insert into public.groups (name, slug, description, created_by)
  values (v_nombre, v_slug, p_descripcion, null)
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
-- 3. El nombre no lo toca nadie más
-- ---------------------------------------------------------------------
create or replace function public.proteger_nombre_de_liga()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if (new.name is distinct from old.name or new.slug is distinct from old.slug)
     and not public.es_dev() then
    raise exception 'El nombre de la liga solo lo cambia quien administra la app'
      using errcode = '42501',
            hint = 'Puedes cambiar los demás ajustes del grupo.';
  end if;
  return new;
end;
$$;

drop trigger if exists groups_proteger_nombre on public.groups;
create trigger groups_proteger_nombre
  before update on public.groups
  for each row execute function public.proteger_nombre_de_liga();

-- ---------------------------------------------------------------------
-- 4. Renombrar, con constancia
-- ---------------------------------------------------------------------
create or replace function public.renombrar_liga(
  p_group_id uuid,
  p_nombre   text
)
returns public.groups
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_grupo public.groups;
  v_antes text;
  v_base  text;
  v_slug  text;
  v_n     int := 0;
begin
  if not public.es_dev() then
    raise exception 'Solo la cuenta de desarrollo puede renombrar una liga'
      using errcode = '42501';
  end if;

  if p_nombre is null or char_length(btrim(p_nombre)) < 2 then
    raise exception 'La liga necesita un nombre' using errcode = '23514';
  end if;

  select name into v_antes from public.groups where id = p_group_id;
  if v_antes is null then
    raise exception 'Esa liga no existe' using errcode = 'P0002';
  end if;

  v_base := coalesce(nullif(public.slugify(p_nombre), ''), 'liga');
  v_slug := v_base;
  while exists (select 1 from public.groups g
                 where g.slug = v_slug and g.id <> p_group_id) loop
    v_n := v_n + 1;
    v_slug := v_base || '-' || v_n;
  end loop;

  update public.groups
  set name = btrim(p_nombre), slug = v_slug
  where id = p_group_id
  returning * into v_grupo;

  perform public.registrar_accion_dev(
    'renombrar_liga', 'groups', p_group_id,
    jsonb_build_object('antes', v_antes, 'despues', v_grupo.name));

  return v_grupo;
end;
$$;

grant execute on function public.renombrar_liga(uuid, text) to authenticated;
