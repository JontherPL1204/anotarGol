-- =====================================================================
-- Anotar Gol - 12 | Los equipos se crean DENTRO de un grupo
-- =====================================================================
-- Un grupo tiene varios equipos y esos equipos se enfrentan entre si.
-- Al probarlo aparecieron dos problemas:
--
-- 1. HUECO FUNCIONAL
--    `create_team` no asignaba grupo, asi que todo equipo creado desde
--    la app nacia fuera de cualquier liga. En las pruebas hubo que
--    asignarlo a mano como postgres, que era la señal de que faltaba.
--
-- 2. AGUJERO DE SEGURIDAD
--    La politica de insercion de `teams` solo exigia
--    `created_by = auth.uid()`. Con eso, cualquiera podia meter un
--    equipo dentro de un grupo ajeno: bastaba con saber su id. Y una vez
--    dentro, su capitan podia retar a los equipos de esa liga privada.
--    Rompia justo la garantia de aislamiento del grupo.
--
-- Se arreglan los dos aqui.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. No se mete un equipo en un grupo del que no eres parte
-- ---------------------------------------------------------------------
drop policy if exists teams_insert on public.teams;
create policy teams_insert on public.teams
  for insert to authenticated
  with check (
    created_by = auth.uid()
    and (group_id is null or public.es_miembro_del_grupo(group_id))
  );

-- Lo mismo al editar: nadie mueve su equipo a una liga ajena.
drop policy if exists teams_update on public.teams;
create policy teams_update on public.teams
  for update to authenticated
  using (public.can_admin_team(id))
  with check (
    public.can_admin_team(id)
    and (group_id is null or public.es_miembro_del_grupo(group_id))
  );

-- ---------------------------------------------------------------------
-- 2. create_team acepta el grupo
-- ---------------------------------------------------------------------
create or replace function public.create_team(
  p_name            text,
  p_short_name      text default null,
  p_primary_color   text default '#1B5E20',
  p_secondary_color text default '#FFD700',
  p_is_public       boolean default false,
  p_group_id        uuid default null
)
returns public.teams
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_team      public.teams;
  v_base_slug text;
  v_slug      text;
  v_suffix    int := 0;
begin
  if auth.uid() is null then
    raise exception 'Debes iniciar sesión para crear un equipo'
      using errcode = '42501';
  end if;

  -- La funcion es SECURITY DEFINER, asi que la comprobacion tiene que
  -- estar aqui: RLS no la va a hacer por nosotros.
  if p_group_id is not null and not public.es_miembro_del_grupo(p_group_id) then
    raise exception 'No perteneces a ese grupo'
      using errcode = '42501',
            hint = 'Únete al grupo con su clave de invitación antes de crear el equipo.';
  end if;

  v_base_slug := coalesce(nullif(public.slugify(p_name), ''), 'equipo');
  v_slug := v_base_slug;

  while exists (select 1 from public.teams t where t.slug = v_slug) loop
    v_suffix := v_suffix + 1;
    v_slug := v_base_slug || '-' || v_suffix;
  end loop;

  insert into public.teams (
    name, short_name, slug, primary_color, secondary_color,
    is_public, group_id, created_by
  )
  values (
    btrim(p_name), nullif(btrim(coalesce(p_short_name, '')), ''), v_slug,
    p_primary_color, p_secondary_color, p_is_public, p_group_id, auth.uid()
  )
  returning * into v_team;

  return v_team;
end;
$$;

grant execute on function public.create_team(text, text, text, text, boolean, uuid)
  to authenticated;

-- La firma vieja de 5 argumentos queda para no romper llamadas
-- existentes; crea el equipo sin grupo, como antes.
drop function if exists public.create_team(text, text, text, text, boolean);

-- ---------------------------------------------------------------------
-- 3. Los equipos de un grupo, para elegir a quien retar
-- ---------------------------------------------------------------------
-- Solo equipos del grupo, sin el propio, y con aviso de si el horario
-- que estas pensando les choca.
create or replace function public.equipos_del_grupo(p_group_id uuid)
returns table (
  id            uuid,
  name          text,
  short_name    text,
  logo_url      text,
  primary_color text,
  jugadores     bigint,
  tiene_capitan boolean,
  es_mi_equipo  boolean
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    t.id, t.name, t.short_name, t.logo_url, t.primary_color,
    (select count(*) from public.players p
      where p.team_id = t.id and p.is_active),
    exists (select 1 from public.team_members tm
            where tm.team_id = t.id and tm.is_captain),
    public.is_team_member(t.id)
  from public.teams t
  where t.group_id = p_group_id
    and public.es_miembro_del_grupo(p_group_id)   -- si no eres del grupo, lista vacia
  order by t.name;
$$;

grant execute on function public.equipos_del_grupo(uuid) to authenticated;

comment on function public.equipos_del_grupo is
  'Equipos de un grupo, para elegir rival. Devuelve vacío si no perteneces al grupo.';

-- ---------------------------------------------------------------------
-- 4. Tabla de posiciones del grupo
-- ---------------------------------------------------------------------
-- Si los equipos de un grupo se enfrentan entre si, la liga necesita su
-- tabla. Cuenta solo partidos terminados entre equipos del mismo grupo.
drop view if exists public.tabla_del_grupo;
create view public.tabla_del_grupo
with (security_invoker = true)
as
with resultados as (
  -- Cada partido aporta una fila por equipo.
  select m.team_id                        as equipo_id,
         t.group_id,
         m.team_score                     as favor,
         m.opponent_score                 as contra
  from public.matches m
  join public.teams t on t.id = m.team_id
  where m.status = 'finished'
    and m.opponent_team_id is not null
    and t.group_id is not null

  union all

  select m.opponent_team_id,
         t.group_id,
         m.opponent_score,
         m.team_score
  from public.matches m
  join public.teams t on t.id = m.opponent_team_id
  where m.status = 'finished'
    and m.opponent_team_id is not null
    and t.group_id is not null
)
select
  r.group_id,
  r.equipo_id,
  t.name                                              as equipo,
  count(*)                                            as jugados,
  count(*) filter (where r.favor > r.contra)           as ganados,
  count(*) filter (where r.favor = r.contra)           as empatados,
  count(*) filter (where r.favor < r.contra)           as perdidos,
  sum(r.favor)                                        as goles_a_favor,
  sum(r.contra)                                       as goles_en_contra,
  sum(r.favor) - sum(r.contra)                        as diferencia,
  count(*) filter (where r.favor > r.contra) * 3
    + count(*) filter (where r.favor = r.contra)      as puntos
from resultados r
join public.teams t on t.id = r.equipo_id
group by r.group_id, r.equipo_id, t.name;

comment on view public.tabla_del_grupo is
  'Posiciones de la liga. Ordenar por puntos desc, diferencia desc, goles_a_favor desc.';

grant select on public.tabla_del_grupo to authenticated;
