-- =====================================================================
-- Anotar Gol - 43 | La plantilla del rival se ve al concretar el partido
-- =====================================================================
-- Decisión del 25/08/2026: los jugadores SÍ pueden ver a los jugadores
-- rivales, pero solo cuando el partido está concretado. Hasta entonces,
-- estar en la misma liga no da derecho a mirar la plantilla ajena.
--
-- Lo que había: `can_view_team` deja ver un equipo a cualquiera del
-- mismo grupo, y `players_select` colgaba de ahí. O sea que un capitán
-- veía los once del rival desde el momento en que entraba a la liga, sin
-- haber acordado nada. Eso ademas dejaba sin sentido la plantilla
-- imaginaria: para qué inventar un rival que ya puedes leer.
--
-- Lo que NO cambia, y es a propósito:
--   * El equipo en sí (nombre, logo, número en la liga) sigue visible
--     para toda la liga. Sin eso no podrías ni saber a quién retar.
--   * `equipo_habilitado()` sigue respondiendo: hay que poder saber si
--     el rival llegó a once ANTES de retarlo, sin ver quiénes son.
--   * `goleadores` agrupa por equipo, así que sigue igual: los tuyos
--     siempre, y los rivales contra los que jugaste.
--
-- "Concretado" es que exista el partido. Lo crea `confirmar_acuerdo`
-- cuando los dos capitanes cierran el trato en el chat temporal. Un
-- partido cancelado no cuenta.
--
-- La visibilidad no se retira después de jugar: si te enfrentaste a
-- ellos, ya los viste. Quitarlo seria fingir que se puede desver algo, y
-- ademas rompería el historial del partido.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. ¿Hay partido entre estos dos equipos?
-- ---------------------------------------------------------------------
-- Se mira en las dos direcciones porque `matches` guarda una sola fila
-- por partido, desde el punto de vista de quien lo creó: uno queda en
-- `team_id` y el otro en `opponent_team_id`.
create or replace function public.hay_partido_concretado(
  p_equipo_a uuid,
  p_equipo_b uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p_equipo_a is not null
     and p_equipo_b is not null
     and exists (
    select 1
    from public.matches m
    where m.status <> 'cancelled'
      and (   (m.team_id = p_equipo_a and m.opponent_team_id = p_equipo_b)
           or (m.team_id = p_equipo_b and m.opponent_team_id = p_equipo_a))
  );
$$;

revoke all on function public.hay_partido_concretado(uuid, uuid) from public;
grant execute on function public.hay_partido_concretado(uuid, uuid) to authenticated;

comment on function public.hay_partido_concretado is
  'Si dos equipos tienen un partido acordado y no cancelado entre ellos.';

-- ---------------------------------------------------------------------
-- 2. ¿Puedo ver esta plantilla?
-- ---------------------------------------------------------------------
-- Tres caminos, y ninguno es "estar en la misma liga":
--   * es mi equipo;
--   * alguno de mis equipos tiene partido concretado con ese;
--   * soy dev, que lo ve todo sin dejar rastro.
--
-- Se recorren TODOS mis equipos porque una misma persona puede estar en
-- varias ligas a la vez. Si mi equipo de la liga B juega contra ellos,
-- los veo; que mi equipo de la liga A no los conozca es irrelevante.
create or replace function public.puedo_ver_plantilla(p_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.es_dev()
      or public.is_team_member(p_team_id)
      or exists (
        select 1
        from public.team_members tm
        where tm.user_id = auth.uid()
          and public.hay_partido_concretado(tm.team_id, p_team_id)
      );
$$;

revoke all on function public.puedo_ver_plantilla(uuid) from public;
grant execute on function public.puedo_ver_plantilla(uuid) to authenticated;

comment on function public.puedo_ver_plantilla is
  'La plantilla ajena se ve al concretar el partido, no por compartir liga.';

-- ---------------------------------------------------------------------
-- 3. Las políticas que dependían de compartir liga
-- ---------------------------------------------------------------------
drop policy if exists players_select on public.players;
create policy players_select on public.players
  for select to authenticated
  using (public.puedo_ver_plantilla(team_id));

-- Una alineación ES la plantilla, dicha de otra forma: si no se puede
-- ver una, no tiene sentido dejar la otra abierta.
drop policy if exists match_lineups_select on public.match_lineups;
create policy match_lineups_select on public.match_lineups
  for select to authenticated
  using (public.puedo_ver_plantilla(team_id));

-- Los rivales que un equipo carga o inventa son sus apuntes privados.
-- Que los leyera toda la liga nunca tuvo sentido.
drop policy if exists rivals_select on public.rivals;
create policy rivals_select on public.rivals
  for select to authenticated
  using (public.is_team_member(team_id) or public.es_dev());

drop policy if exists rival_players_select on public.rival_players;
create policy rival_players_select on public.rival_players
  for select to authenticated
  using (public.is_team_member(team_id) or public.es_dev());
