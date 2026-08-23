-- =====================================================================
-- Anotar Gol - 21 | La cédula es el id del jugador
-- =====================================================================
-- Dos reglas pedidas el 24/08/2026:
--
--   * El jugador, ya dentro, puede cambiar su nombre y su dorsal, pero
--     su identidad es la cédula y esa NO se toca. Si la cédula pudiera
--     editarse, la ficha dejaría de ser de quien es y el vínculo con la
--     cuenta se rompería.
--   * El capitán saca a alguien del equipo escribiendo su cédula, con
--     una confirmación de por medio.
--
-- Nota sobre "sacar": es baja lógica, no borrado. Los goles del jugador
-- siguen en el historial y en el ranking, que es lo correcto: el gol se
-- metió, aunque después se haya ido del club.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. La cédula no se cambia
-- ---------------------------------------------------------------------
create or replace function public.proteger_cedula_jugador()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- Ponerla cuando faltaba sí se permite: es completar la ficha.
  if old.cedula is not null and new.cedula is distinct from old.cedula then
    raise exception 'La cédula no se puede cambiar: es la identidad del jugador'
      using errcode = '42501',
            hint = 'Si te equivocaste, saca la ficha y créala de nuevo con la cédula correcta.';
  end if;

  -- El jugador puede corregir lo suyo, no cambiarse de equipo ni de dueño.
  if not public.can_edit_squad(old.team_id) then
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

drop trigger if exists players_proteger_cedula on public.players;
create trigger players_proteger_cedula
  before update on public.players
  for each row execute function public.proteger_cedula_jugador();

-- ---------------------------------------------------------------------
-- 2. El jugador edita su propia ficha
-- ---------------------------------------------------------------------
-- Antes solo podían los roles con permiso sobre la plantilla. Ahora
-- también el dueño de la ficha, limitado por el trigger de arriba.
drop policy if exists players_update on public.players;
create policy players_update on public.players
  for update to authenticated
  using (public.can_edit_squad(team_id) or user_id = auth.uid())
  with check (public.can_edit_squad(team_id) or user_id = auth.uid());

-- ---------------------------------------------------------------------
-- 3. Buscar por cédula antes de sacar
-- ---------------------------------------------------------------------
-- La confirmación necesita mostrar a quién se va a sacar. Preguntar
-- "¿seguro?" sin decir el nombre es una forma de que alguien saque al
-- jugador equivocado.
create or replace function public.buscar_jugador_por_cedula(
  p_team_id uuid,
  p_cedula  text
)
returns table (
  id          uuid,
  full_name   text,
  number      smallint,
  posicion    text,
  cedula      text,
  registrado  boolean,
  goles       bigint
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    p.id,
    p.full_name,
    p.number,
    coalesce(p.position_detail, p.position::text),
    p.cedula,
    p.user_id is not null,
    (select count(*) from public.match_events e
      where e.player_id = p.id and e.type = 'goal' and not e.is_own_goal)
  from public.players p
  where p.team_id = p_team_id
    and p.cedula = btrim(p_cedula)
    and p.is_active
    and public.can_view_team(p_team_id);
$$;

grant execute on function public.buscar_jugador_por_cedula(uuid, text) to authenticated;

-- ---------------------------------------------------------------------
-- 4. Sacar del equipo por cédula
-- ---------------------------------------------------------------------
create or replace function public.sacar_jugador_por_cedula(
  p_team_id uuid,
  p_cedula  text
)
returns public.players
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_j public.players;
begin
  if not (public.can_captain(p_team_id) or public.can_edit_team(p_team_id)) then
    raise exception 'Solo el capitán o el cuerpo técnico pueden sacar jugadores'
      using errcode = '42501';
  end if;

  select * into v_j
  from public.players
  where team_id = p_team_id and cedula = btrim(p_cedula) and is_active;

  if v_j.id is null then
    raise exception 'No hay ningún jugador activo con esa cédula en el equipo'
      using errcode = 'P0002',
            hint = 'Revisa el número: son 10 dígitos.';
  end if;

  -- Baja lógica: los goles se quedan en el historial.
  update public.players
  set is_active = false, user_id = null
  where id = v_j.id
  returning * into v_j;

  -- Y deja de ser miembro del equipo, si tenía cuenta vinculada.
  if v_j.user_id is not null then
    delete from public.team_members
    where team_id = p_team_id and user_id = v_j.user_id;
  end if;

  return v_j;
end;
$$;

grant execute on function public.sacar_jugador_por_cedula(uuid, text) to authenticated;

comment on function public.sacar_jugador_por_cedula is
  'Baja lógica del jugador. Conserva sus goles en el historial y el ranking.';

-- ---------------------------------------------------------------------
-- 5. Mis fichas: en qué equipos juego
-- ---------------------------------------------------------------------
drop view if exists public.mis_fichas;
create view public.mis_fichas
with (security_invoker = true)
as
select
  p.id            as player_id,
  p.team_id,
  t.name          as equipo,
  t.group_id,
  g.name          as grupo,
  p.full_name,
  p.number,
  p.position,
  p.position_detail,
  p.cedula,
  p.is_active,
  exists (
    select 1 from public.team_members tm
    where tm.team_id = p.team_id and tm.user_id = p.user_id and tm.is_captain
  ) as soy_capitan
from public.players p
join public.teams t on t.id = p.team_id
left join public.groups g on g.id = t.group_id
where p.user_id = auth.uid();

grant select on public.mis_fichas to authenticated;

comment on view public.mis_fichas is
  'Los equipos donde el usuario está fichado, con los datos que puede editar.';
