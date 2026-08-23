-- =====================================================================
-- Anotar Gol - 31 | Borrar la cuenta cuando tienes ficha de jugador
-- =====================================================================
-- Sintoma:
--   Borrar un usuario que está fichado en un equipo falla con
--   "Solo puedes cambiar tu nombre, tu dorsal y tu posición".
--
-- Causa:
--   `players.user_id` tiene `on delete set null`. Al borrar la cuenta,
--   Postgres pone ese campo en null, y eso dispara el trigger que
--   protege la ficha. Durante el arrastre no hay sesión, así que
--   `auth.uid()` es null, `can_edit_squad` da falso, y el trigger corta.
--
-- Por qué importa:
--   Es exactamente el mismo tropiezo que ya hubo con `protect_last_owner`
--   (migración 10): una regla pensada para impedir un abuso terminó
--   bloqueando el borrado de cuenta. Y poder borrar la cuenta desde la
--   app es requisito de Google Play y de la App Store para cualquier app
--   con registro.
--
-- Arreglo:
--   Se reconoce el arrastre: si `user_id` pasa a null porque la cuenta
--   ya no existe, se deja pasar. La ficha se queda en el equipo, sin
--   dueño, y sus goles siguen en el historial.
-- =====================================================================

create or replace function public.proteger_cedula_jugador()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_reclama_su_ficha boolean;
  v_cuenta_borrada   boolean;
begin
  if old.cedula is not null and new.cedula is distinct from old.cedula then
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

  -- La ficha queda libre porque su dueño borró la cuenta. No es alguien
  -- manipulando datos ajenos: es el arrastre de auth.users.
  v_cuenta_borrada :=
       old.user_id is not null
   and new.user_id is null
   and not exists (select 1 from auth.users u where u.id = old.user_id);

  if v_cuenta_borrada then
    return new;
  end if;

  -- Reclamar la ficha propia.
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
-- Borrar la propia cuenta desde la app
-- ---------------------------------------------------------------------
-- Las dos tiendas lo exigen, y hacerlo bien implica avisar de lo que se
-- pierde y de lo que queda: los goles anotados no se borran, porque el
-- gol ocurrió y el resultado del partido depende de él.
create or replace function public.que_pasa_si_borro_mi_cuenta()
returns table (
  equipos       bigint,
  grupos        bigint,
  fichas        bigint,
  goles         bigint,
  soy_capitan_de bigint,
  soy_owner_de  bigint
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    (select count(*) from public.team_members  where user_id = auth.uid()),
    (select count(*) from public.group_members where user_id = auth.uid()),
    (select count(*) from public.players       where user_id = auth.uid()),
    (select count(*) from public.match_events e
       join public.players p on p.id = e.player_id
      where p.user_id = auth.uid() and e.type = 'goal'),
    (select count(*) from public.team_members
      where user_id = auth.uid() and is_captain),
    (select count(*) from public.team_members
      where user_id = auth.uid() and role = 'owner');
$$;

grant execute on function public.que_pasa_si_borro_mi_cuenta() to authenticated;

comment on function public.que_pasa_si_borro_mi_cuenta is
  'Qué arrastra el borrado de cuenta, para poder decírselo antes de confirmar.';
