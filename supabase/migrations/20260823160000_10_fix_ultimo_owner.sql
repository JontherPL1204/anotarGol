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
