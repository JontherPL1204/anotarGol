-- =====================================================================
-- Anotar Gol - 33 | El número del equipo en su liga, y el escudo
-- =====================================================================
-- Requisito del 24/08/2026:
--
--   * El nombre del equipo lo pone el capitán y es OBLIGATORIO.
--   * El escudo (logo) es opcional.
--   * En el despliegue de la liga, el dev ve los equipos numerados:
--     "Equipo 1", "Equipo 2"... y en cuanto el capitán le pone nombre,
--     pasa a ver "Equipo 1 (Halcones FC)".
--   * Los jugadores ven solo el nombre: "Halcones FC".
--
-- Lo que faltaba: el número. Un equipo no tenía posición dentro de su
-- liga, así que no había forma de decir "Equipo 1". Se asigna solo al
-- crearlo y no cambia: es la referencia con la que el dev habla de ese
-- club antes y después de que tenga nombre.
--
-- Nota: el nombre ya era obligatorio (check de 2 a 80 caracteres en
-- `teams.name`), así que "Equipo 1" a secas solo se ve si el club se
-- creó desde la base. Aun así el número sirve: ordena la liga y le da
-- al dev una referencia estable.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. El número dentro de la liga
-- ---------------------------------------------------------------------
alter table public.teams
  add column if not exists numero_en_grupo smallint;

comment on column public.teams.numero_en_grupo is
  'Posición del club dentro de su liga. Se asigna al crearlo y no cambia.';

-- Dos equipos de una misma liga no pueden compartir número.
create unique index if not exists teams_numero_por_grupo
  on public.teams (group_id, numero_en_grupo)
  where group_id is not null and numero_en_grupo is not null;

create or replace function public.asignar_numero_de_equipo()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.group_id is null or new.numero_en_grupo is not null then
    return new;
  end if;

  -- El bloqueo por grupo evita que dos altas simultáneas se lleven el
  -- mismo número. Es por liga, así que no traba a las demás.
  perform pg_advisory_xact_lock(hashtext(new.group_id::text));

  select coalesce(max(numero_en_grupo), 0) + 1
    into new.numero_en_grupo
  from public.teams
  where group_id = new.group_id;

  return new;
end;
$$;

drop trigger if exists teams_numerar on public.teams;
create trigger teams_numerar
  before insert on public.teams
  for each row execute function public.asignar_numero_de_equipo();

-- Los que ya existen quedan numerados por antigüedad.
do $$
declare
  r record;
begin
  for r in
    select id, row_number() over (partition by group_id order by created_at) as n
    from public.teams
    where group_id is not null and numero_en_grupo is null
  loop
    update public.teams set numero_en_grupo = r.n where id = r.id;
  end loop;
end
$$;

-- ---------------------------------------------------------------------
-- 2. Cómo se llama el equipo, según quién mire
-- ---------------------------------------------------------------------
-- El dev necesita la referencia numérica para hablar de un club dentro
-- de una liga; el jugador solo quiere ver el nombre de su equipo.
create or replace function public.etiqueta_equipo(
  p_numero smallint,
  p_nombre text,
  p_para_dev boolean default false
)
returns text
language sql
immutable
as $$
  select case
    when not p_para_dev or p_numero is null then p_nombre
    when p_nombre is null or btrim(p_nombre) = '' then format('Equipo %s', p_numero)
    else format('Equipo %s (%s)', p_numero, p_nombre)
  end;
$$;

grant execute on function public.etiqueta_equipo(smallint, text, boolean) to authenticated;

-- ---------------------------------------------------------------------
-- 3. El despliegue de la liga para el dev
-- ---------------------------------------------------------------------
drop view if exists public.panel_dev_equipos;
create view public.panel_dev_equipos
with (security_invoker = true)
as
select
  t.id,
  t.group_id,
  g.name                as liga,
  t.numero_en_grupo     as numero,
  t.name                as nombre,
  t.logo_url,
  public.etiqueta_equipo(t.numero_en_grupo, t.name, true) as etiqueta,
  t.plantilla_confirmada,
  public.equipo_habilitado(t.id) as habilitado,
  (select count(*) from public.players p
    where p.team_id = t.id and p.is_active)                        as jugadores,
  (select count(*) from public.players p
    where p.team_id = t.id and p.is_active and p.cedula is not null) as con_cedula,
  (select count(*) from public.team_members tm
    where tm.team_id = t.id)                                       as miembros,
  exists (select 1 from public.team_members tm
           where tm.team_id = t.id and tm.is_captain)              as tiene_capitan,
  t.created_at
from public.teams t
join public.groups g on g.id = t.group_id
where public.es_dev()
order by g.name, t.numero_en_grupo;

grant select on public.panel_dev_equipos to authenticated;

comment on view public.panel_dev_equipos is
  'Equipos de cada liga vistos por el dev: "Equipo 1 (Halcones FC)". Vacía para los demás.';

-- Los equipos de la liga, tal como los ve un integrante: solo el nombre.
--
-- Se suelta primero porque gana columnas: `create or replace` no puede
-- cambiar el tipo de retorno de una función que ya existe.
drop function if exists public.equipos_del_grupo(uuid);

create or replace function public.equipos_del_grupo(p_group_id uuid)
returns table (
  id            uuid,
  name          text,
  short_name    text,
  logo_url      text,
  primary_color text,
  numero        smallint,
  jugadores     bigint,
  tiene_capitan boolean,
  habilitado    boolean,
  es_mi_equipo  boolean
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    t.id,
    -- Para el dev, con su número delante; para el resto, el nombre a secas.
    public.etiqueta_equipo(t.numero_en_grupo, t.name, public.es_dev()),
    t.short_name, t.logo_url, t.primary_color,
    t.numero_en_grupo,
    (select count(*) from public.players p
      where p.team_id = t.id and p.is_active),
    exists (select 1 from public.team_members tm
             where tm.team_id = t.id and tm.is_captain),
    public.equipo_habilitado(t.id),
    public.is_team_member(t.id)
  from public.teams t
  where t.group_id = p_group_id
    and public.es_miembro_del_grupo(p_group_id)
  order by t.numero_en_grupo;
$$;

grant execute on function public.equipos_del_grupo(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 4. Nombre y escudo del equipo
-- ---------------------------------------------------------------------
-- El nombre es obligatorio; el escudo, opcional. Se sube al bucket
-- `team-logos` bajo la carpeta del equipo, que es lo que las políticas
-- de storage ya exigen.
create or replace function public.actualizar_identidad_equipo(
  p_team_id    uuid,
  p_nombre     text,
  p_short_name text default null,
  p_logo_url   text default null
)
returns public.teams
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_team public.teams;
begin
  if not (public.can_captain(p_team_id) or public.can_admin_team(p_team_id)) then
    raise exception 'Solo el capitán o un administrador del club pueden cambiar esto'
      using errcode = '42501';
  end if;

  if p_nombre is null or char_length(btrim(p_nombre)) < 2 then
    raise exception 'El equipo necesita un nombre'
      using errcode = '23514',
            hint = 'El escudo es opcional, el nombre no.';
  end if;

  update public.teams
  set name       = btrim(p_nombre),
      short_name = nullif(btrim(coalesce(p_short_name, '')), ''),
      -- Pasar null deja el escudo como estaba; para quitarlo se manda ''.
      logo_url   = case
                     when p_logo_url is null then logo_url
                     when btrim(p_logo_url) = '' then null
                     else btrim(p_logo_url)
                   end
  where id = p_team_id
  returning * into v_team;

  if v_team.id is null then
    raise exception 'Ese equipo no existe' using errcode = 'P0002';
  end if;

  return v_team;
end;
$$;

grant execute on function public.actualizar_identidad_equipo(uuid, text, text, text)
  to authenticated;
