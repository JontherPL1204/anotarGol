-- =====================================================================
-- Anotar Gol - 41 | mi_situacion() tiene que saber si eres dev
-- =====================================================================
-- Callejon sin salida encontrado al probar el registro:
--
--   La puerta manda a la casilla de la clave a quien no pertenece a
--   ninguna liga. Pero un dev NO pertenece a ninguna liga, por diseño:
--   no figura en ningun grupo ni equipo. Resultado: la app lo dejaba
--   atrapado pidiendole una clave de liga que no tiene por que tener.
--
-- `mi_situacion()` es la funcion que decide a que pantalla va el
-- usuario, asi que es ahi donde tiene que constar.
-- =====================================================================

drop function if exists public.mi_situacion();

create or replace function public.mi_situacion()
returns table (
  tiene_grupo   boolean,
  tiene_equipo  boolean,
  puede_fundar  boolean,
  group_id      uuid,
  grupo         text,
  team_id       uuid,
  equipo        text,
  soy_capitan   boolean,
  tengo_cedula  boolean,
  soy_dev       boolean
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with mi_ficha as (
    select tm.team_id, t.name as equipo, t.group_id, tm.is_captain
    from public.team_members tm
    join public.teams t on t.id = tm.team_id
    where tm.user_id = auth.uid()
    order by tm.created_at
    limit 1
  ),
  mi_grupo as (
    select gm.group_id, g.name, gm.puede_fundar_equipo
    from public.group_members gm
    join public.groups g on g.id = gm.group_id
    where gm.user_id = auth.uid()
    order by gm.joined_at
    limit 1
  )
  select
    (select count(*) from public.group_members where user_id = auth.uid()) > 0,
    (select count(*) from public.team_members  where user_id = auth.uid()) > 0,
    coalesce((select puede_fundar_equipo from mi_grupo), false),
    coalesce((select group_id from mi_ficha), (select group_id from mi_grupo)),
    coalesce((select g.name from public.groups g
               where g.id = (select group_id from mi_ficha)),
             (select name from mi_grupo)),
    (select team_id from mi_ficha),
    (select equipo from mi_ficha),
    coalesce((select is_captain from mi_ficha), false),
    (select cedula is not null from public.profiles where id = auth.uid()),
    public.es_dev();
$$;

grant execute on function public.mi_situacion() to authenticated;

comment on function public.mi_situacion is
  'Una sola respuesta para saber a qué pantalla llevar al usuario. soy_dev evita que la puerta atrape a quien no pertenece a ninguna liga por diseño.';
