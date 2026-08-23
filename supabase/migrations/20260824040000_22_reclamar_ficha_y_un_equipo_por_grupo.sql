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
