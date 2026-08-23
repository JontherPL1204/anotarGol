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
