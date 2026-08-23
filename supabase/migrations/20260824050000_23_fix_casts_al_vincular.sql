-- =====================================================================
-- Anotar Gol - 23 | Corrección: casts al vincular fichas
-- =====================================================================
-- `registrar_mi_cedula` fallaba con:
--   column "role" is of type group_role but expression is of type text
--
-- Causa: en `insert ... select`, Postgres NO infiere el tipo del literal
-- como sí hace en `insert ... values`. Los 'player' y 'member' llegaban
-- como text a columnas enum.
--
-- Es el mismo tropiezo que en la migración 19 con `estado_solicitud`.
-- Se revisaron todas las migraciones buscando el patrón; estos dos eran
-- los únicos insert-select restantes contra columnas enum.
-- =====================================================================

create or replace function public.vincular_fichas_por_cedula(p_user_id uuid)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_cedula text;
  v_n      int;
begin
  select cedula into v_cedula from public.profiles where id = p_user_id;
  if v_cedula is null then
    return 0;
  end if;

  update public.players
  set user_id = p_user_id
  where cedula = v_cedula and user_id is distinct from p_user_id;

  get diagnostics v_n = row_count;

  -- Estar fichado en un equipo es ser parte del equipo.
  insert into public.team_members (team_id, user_id, role)
  select p.team_id, p_user_id, 'player'::public.team_role
  from public.players p
  where p.cedula = v_cedula and p.is_active
  on conflict (team_id, user_id) do nothing;

  -- Y al equipo se llega por su grupo.
  insert into public.group_members (group_id, user_id, role, puede_fundar_equipo)
  select distinct t.group_id, p_user_id, 'member'::public.group_role, false
  from public.players p
  join public.teams t on t.id = p.team_id
  where p.cedula = v_cedula and p.is_active and t.group_id is not null
  on conflict (group_id, user_id) do nothing;

  return v_n;
end;
$$;

grant execute on function public.vincular_fichas_por_cedula(uuid) to authenticated;
