-- =====================================================================
-- Anotar Gol - 19 | Dos correcciones de la migración 17
-- =====================================================================
-- Ambas aparecieron al probar el flujo completo contra la base.
--
-- 1. responder_solicitud fallaba con:
--      column "estado" is of type estado_solicitud but expression is of
--      type text
--    El CASE devolvía texto sin castear al enum. Se arregla con el cast
--    explícito.
--
-- 2. La bandeja del administrador mostraba `solicitante: null`.
--    La vista es security_invoker y `profiles_select` solo dejaba ver el
--    perfil propio o el de compañeros de EQUIPO. El administrador de un
--    grupo no comparte equipo con quien le escribe, así que veía la
--    solicitud pero no el nombre de quien la manda: inservible para
--    decidir. Se agrega la visibilidad por GRUPO.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. El cast que faltaba
-- ---------------------------------------------------------------------
create or replace function public.responder_solicitud(
  p_solicitud_id uuid,
  p_aprobar      boolean
)
returns public.solicitudes_equipo
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_s public.solicitudes_equipo;
begin
  select * into v_s from public.solicitudes_equipo where id = p_solicitud_id;

  if v_s.id is null then
    raise exception 'Esa solicitud no existe' using errcode = 'P0002';
  end if;

  if not public.es_admin_del_grupo(v_s.group_id) then
    raise exception 'Solo un administrador del grupo puede responder'
      using errcode = '42501';
  end if;

  if v_s.estado <> 'pendiente' then
    raise exception 'Esa solicitud ya fue respondida' using errcode = '23514';
  end if;

  if p_aprobar then
    update public.group_members
    set puede_fundar_equipo = true
    where group_id = v_s.group_id and user_id = v_s.user_id;
  end if;

  update public.solicitudes_equipo
  set estado = (case when p_aprobar then 'aprobada' else 'rechazada' end)
                 ::public.estado_solicitud,
      resuelta_por = auth.uid(),
      resuelta_at = now()
  where id = p_solicitud_id
  returning * into v_s;

  return v_s;
end;
$$;

grant execute on function public.responder_solicitud(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------
-- 2. Ver el nombre de la gente de tu grupo
-- ---------------------------------------------------------------------
create or replace function public.comparte_grupo_conmigo(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.group_members mio
    join public.group_members suyo on suyo.group_id = mio.group_id
    where mio.user_id = auth.uid()
      and suyo.user_id = p_user_id
  );
$$;

grant execute on function public.comparte_grupo_conmigo(uuid) to authenticated;

-- El perfil solo tiene nombre, correo y avatar. Dentro de una liga hace
-- falta poder ponerle cara a quien juega, capitanea o pide permiso.
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated
  using (
    id = auth.uid()
    or public.es_dev()
    or public.shares_team_with(id)
    or public.comparte_grupo_conmigo(id)
  );
