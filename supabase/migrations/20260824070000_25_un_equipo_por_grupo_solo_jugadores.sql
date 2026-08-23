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
