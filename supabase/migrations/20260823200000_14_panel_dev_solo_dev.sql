-- =====================================================================
-- Anotar Gol - 14 | El panel del dev es solo del dev
-- =====================================================================
-- Al probar la migracion 13 aparecio esto:
--
--   filas del panel para un usuario normal: 1
--
-- La vista `panel_dev_grupos` es security_invoker, asi que heredaba la
-- politica `groups_select`: un miembro del grupo ve su propia fila. No
-- es una fuga entre grupos, pero expone a cualquier integrante el conteo
-- de miembros y de invitaciones activas de su liga, que es informacion
-- de administracion.
--
-- Se agrega el filtro explicito: si no eres dev, la vista esta vacia.
-- =====================================================================

drop view if exists public.panel_dev_grupos;
create view public.panel_dev_grupos
with (security_invoker = true)
as
select
  g.id,
  g.name,
  g.slug,
  g.description,
  g.created_at,
  (select count(*) from public.teams t where t.group_id = g.id)          as equipos,
  (select count(*) from public.group_members gm where gm.group_id = g.id) as miembros,
  (select count(*) from public.group_invites gi
     where gi.group_id = g.id and gi.is_active)                          as invitaciones_activas,
  (select count(*) from public.matches m
     join public.teams t2 on t2.id = m.team_id
    where t2.group_id = g.id)                                            as partidos
from public.groups g
where public.es_dev();

grant select on public.panel_dev_grupos to authenticated;

comment on view public.panel_dev_grupos is
  'Resumen de todos los grupos. Vacía para quien no sea la cuenta de desarrollo.';
