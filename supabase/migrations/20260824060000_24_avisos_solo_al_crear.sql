-- =====================================================================
-- Anotar Gol - 24 | Los avisos de posición son solo del armado inicial
-- =====================================================================
-- Ajuste del 24/08/2026: los avisos de posiciones repetidas le sirven al
-- capitán mientras arma los 11 obligatorios. Después estorban: un club
-- con 20 fichados va a tener cuatro laterales derechos y está bien.
--
-- Se resuelve con una marca explícita en vez de adivinar por el número
-- de jugadores: `plantilla_confirmada`. El capitán la pulsa una vez,
-- cuando termina de armar el equipo, y los avisos de composición dejan
-- de aparecer. Lo que sí sigue apareciendo siempre es lo que impide
-- jugar: no llegar a 11 con cédula.
--
-- Por qué una marca y no "cuando llegue a 11": justo al cargar al
-- jugador 11 es cuando el capitán MÁS quiere ver "ojo, tienes dos
-- laterales derechos". Si los avisos se apagaran solos en ese instante,
-- nunca los vería.
-- =====================================================================

alter table public.teams
  add column if not exists plantilla_confirmada boolean not null default false;

comment on column public.teams.plantilla_confirmada is
  'El capitán ya revisó el armado inicial. Apaga los avisos de composición.';

create or replace function public.confirmar_plantilla(p_team_id uuid)
returns public.teams
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_team public.teams;
begin
  if not (public.can_captain(p_team_id) or public.can_edit_team(p_team_id)) then
    raise exception 'Solo el capitán o el cuerpo técnico pueden confirmar la plantilla'
      using errcode = '42501';
  end if;

  if not public.equipo_habilitado(p_team_id) then
    raise exception 'Todavía faltan jugadores con cédula para llegar a 11'
      using errcode = '23514';
  end if;

  update public.teams
  set plantilla_confirmada = true
  where id = p_team_id
  returning * into v_team;

  return v_team;
end;
$$;

grant execute on function public.confirmar_plantilla(uuid) to authenticated;

-- Volver a abrir el armado, si el capitán quiere revisar de nuevo.
create or replace function public.reabrir_plantilla(p_team_id uuid)
returns public.teams
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_team public.teams;
begin
  if not (public.can_captain(p_team_id) or public.can_edit_team(p_team_id)) then
    raise exception 'Solo el capitán o el cuerpo técnico pueden hacer esto'
      using errcode = '42501';
  end if;

  update public.teams set plantilla_confirmada = false
  where id = p_team_id returning * into v_team;

  return v_team;
end;
$$;

grant execute on function public.reabrir_plantilla(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- Avisos: bloqueos siempre, composición solo mientras se arma
-- ---------------------------------------------------------------------
create or replace function public.avisos_de_plantilla(p_team_id uuid)
returns table (
  tipo     text,     -- 'bloqueo' | 'aviso'
  mensaje  text
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_total     int;
  v_con_ced   int;
  v_porteros  int;
  v_confirmada boolean;
  r           record;
begin
  select plantilla_confirmada into v_confirmada
  from public.teams where id = p_team_id;

  select count(*) filter (where is_active),
         count(*) filter (where is_active and cedula is not null),
         count(*) filter (where is_active and position = 'GK')
    into v_total, v_con_ced, v_porteros
  from public.players where team_id = p_team_id;

  -- Esto impide jugar, así que se dice siempre.
  if v_con_ced < 11 then
    return query select 'bloqueo'::text,
      format('Faltan %s jugadores con cédula para completar los 11 obligatorios.',
             11 - v_con_ced);
  end if;

  if v_total > v_con_ced then
    return query select 'aviso'::text,
      format('%s jugador(es) sin cédula: no cuentan para los 11.',
             v_total - v_con_ced);
  end if;

  -- De aquí para abajo, solo mientras el capitán arma el equipo.
  if coalesce(v_confirmada, false) then
    return;
  end if;

  if v_porteros = 0 then
    return query select 'aviso'::text, 'No hay ningún portero en la plantilla.';
  elsif v_porteros > 1 then
    return query select 'aviso'::text,
      format('Hay %s porteros. Normalmente juega uno.', v_porteros);
  end if;

  for r in
    select position_detail, count(*) n
    from public.players
    where team_id = p_team_id and is_active and position_detail is not null
    group by position_detail having count(*) > 1
  loop
    return query select 'aviso'::text,
      format('%s jugadores puestos como "%s".', r.n, r.position_detail);
  end loop;

  return;
end;
$$;

grant execute on function public.avisos_de_plantilla(uuid) to authenticated;

-- La vista de estado lleva la marca, para que la app sepa si ofrecer el
-- botón de confirmar.
drop view if exists public.estado_plantilla;
create view public.estado_plantilla
with (security_invoker = true)
as
select
  t.id                                   as team_id,
  t.name                                 as equipo,
  t.group_id,
  t.plantilla_confirmada,
  count(p.*) filter (where p.is_active)                          as jugadores,
  count(p.*) filter (where p.is_active and p.cedula is not null) as con_cedula,
  count(p.*) filter (where p.is_active and p.user_id is not null) as ya_registrados,
  greatest(0, 11 - count(p.*) filter (where p.is_active and p.cedula is not null))
                                                                 as faltan,
  public.equipo_habilitado(t.id)                                 as habilitado
from public.teams t
left join public.players p on p.team_id = t.id
group by t.id, t.name, t.group_id, t.plantilla_confirmada;

grant select on public.estado_plantilla to authenticated;
