-- =====================================================================
-- Anotar Gol - 36 | Cerrar los permisos de las funciones
-- =====================================================================
-- El Security Advisor de Supabase levantó decenas de avisos. Al mirar
-- los ACL resultaron ser dos causas, no decenas de problemas:
--
-- 1) `=X/postgres` en el ACL de TODAS las funciones.
--    Es el permiso a PUBLIC, que PostgreSQL otorga por defecto a
--    cualquier función que se cree. Por eso las 82 funciones del esquema
--    eran ejecutables por `anon`, incluidas 70 con SECURITY DEFINER.
--
--    Los `grant execute ... to authenticated` que veníamos escribiendo
--    eran redundantes: el permiso ya estaba dado a todo el mundo. Lo que
--    faltaba era el REVOKE.
--
--    No era una puerta abierta a los datos —cada función comprueba
--    permisos por dentro y RLS sigue en pie—, pero sí superficie de
--    ataque gratuita: funciones internas y de trigger expuestas en
--    /rest/v1/rpc/ sin ninguna razón.
--
-- 2) Seis funciones auxiliares sin `search_path` fijo. Ninguna es
--    SECURITY DEFINER, así que el riesgo es menor, pero es la misma
--    precaución que ya tenían las demás y cuesta una línea.
--
-- Además: ya no hay acceso anónimo. Sin hinchas, nadie mira nada sin
-- iniciar sesión, así que `anon` sale también de las políticas.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. search_path fijo en las seis que faltaban
-- ---------------------------------------------------------------------
alter function public.set_updated_at()                     set search_path = public, pg_temp;
alter function public.slugify(text)                        set search_path = public, pg_temp;
alter function public.safe_uuid(text)                      set search_path = public, pg_temp;
alter function public.es_cedula_valida(text)               set search_path = public, pg_temp;
alter function public.etiqueta_equipo(smallint, text, boolean) set search_path = public, pg_temp;
alter function public.letra_de_liga(int)                   set search_path = public, pg_temp;

-- ---------------------------------------------------------------------
-- 2. Quitar el permiso que PostgreSQL da por defecto
-- ---------------------------------------------------------------------
revoke execute on all functions in schema public from public;
revoke execute on all functions in schema public from anon;

-- Y que las que se creen de aquí en adelante nazcan cerradas, para no
-- volver a arrastrar el mismo agujero.
alter default privileges in schema public revoke execute on functions from public;

-- ---------------------------------------------------------------------
-- 3. Devolver el permiso solo a quien lo necesita
-- ---------------------------------------------------------------------
grant execute on all functions in schema public to authenticated;

-- Las funciones de trigger no se llaman nunca a mano: las invoca el
-- motor con los permisos del dueño de la tabla. Exponerlas en la API no
-- sirve para nada y solo agranda la superficie.
do $$
declare
  f record;
begin
  for f in
    select p.oid::regprocedure as firma
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    join pg_type t on t.oid = p.prorettype
    where n.nspname = 'public' and t.typname = 'trigger'
  loop
    execute format('revoke execute on function %s from authenticated, anon, public', f.firma);
  end loop;
end
$$;

-- ---------------------------------------------------------------------
-- 4. Se acabó el acceso anónimo
-- ---------------------------------------------------------------------
-- Con el modelo de ligas privadas y sin hinchas, nadie lee nada sin
-- iniciar sesión. Dejar `anon` en las políticas solo servía para que una
-- consulta anónima fallara con un error confuso en vez de no ver nada.
drop policy if exists teams_select on public.teams;
create policy teams_select on public.teams
  for select to authenticated
  using (
    public.es_dev()
    or public.is_team_member(id)
    or (group_id is not null
        and is_discoverable
        and public.es_miembro_del_grupo(group_id))
    or (group_id is null and is_public)
  );

do $$
declare
  t text;
begin
  foreach t in array array[
    'seasons', 'players', 'matches', 'match_events', 'match_lineups',
    'team_settings', 'rivals', 'rival_players']
  loop
    execute format('drop policy if exists %I on public.%I', t || '_select', t);
  end loop;

  -- matches lleva su propia condición: el rival también tiene que verlo.
  foreach t in array array[
    'seasons', 'players', 'match_events', 'match_lineups',
    'team_settings', 'rivals', 'rival_players']
  loop
    execute format($fmt$
      create policy %I on public.%I
        for select to authenticated
        using (public.can_view_team(team_id))
    $fmt$, t || '_select', t);
  end loop;
end
$$;

create policy matches_select on public.matches
  for select to authenticated
  using (
    public.can_view_team(team_id)
    or (opponent_team_id is not null and public.is_team_member(opponent_team_id))
  );

-- Las vistas siguen siendo legibles por quien tenga sesión; el filtro
-- real lo hacen las políticas de las tablas que hay debajo.
revoke select on public.player_stats, public.match_summary, public.goleadores,
                 public.historial_goles, public.cronograma, public.partido_en_vivo
  from anon;

-- ---------------------------------------------------------------------
-- 5. Storage se queda abierto a propósito
-- ---------------------------------------------------------------------
-- Los escudos y las fotos se cargan con `Image.network`, que no manda la
-- cabecera de autenticación. Si se cerrara la lectura, no se vería
-- ninguna imagen. Son archivos de imagen en un bucket público: no hay
-- dato sensible ahí, y la escritura sigue restringida por equipo.
comment on policy anotar_gol_media_read on storage.objects is
  'Lectura abierta a propósito: las imágenes se cargan sin cabecera de auth.';
