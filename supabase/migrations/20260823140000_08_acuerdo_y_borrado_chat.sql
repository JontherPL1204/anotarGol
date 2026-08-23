-- =====================================================================
-- Anotar Gol - 08 | "Quedaron de acuerdo" y borrado del chat temporal
-- =====================================================================
-- Ajuste del flujo pedido el 23/08/2026:
--
--   El chat entre capitanes es temporal y existe solo para coordinar.
--   Cuando pulsan "Quedaron de acuerdo", se avisa que el chat se va a
--   borrar; si confirman, se borra, se registra el partido acordado y
--   RECIEN AHI aparece en el cronograma.
--
-- El borrado no es cosmetico: el chat de coordinacion no tiene por que
-- quedarse ocupando espacio para siempre.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. El chat muere con el reto
-- ---------------------------------------------------------------------
-- Cubre todas las salidas: acordado, rechazado, cancelado o vencido.
-- Ponerlo en un trigger y no en cada RPC evita que un camino nuevo se
-- olvide de limpiar.
create or replace function public.borrar_chat_del_reto()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.status <> 'pending' and old.status = 'pending' then
    delete from public.challenge_messages where challenge_id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists challenges_borrar_chat on public.challenges;
create trigger challenges_borrar_chat
  after update on public.challenges
  for each row execute function public.borrar_chat_del_reto();

comment on function public.borrar_chat_del_reto is
  'Borra el chat temporal en cuanto el reto deja de estar en negociación.';

-- ---------------------------------------------------------------------
-- 2. Confirmar el acuerdo
-- ---------------------------------------------------------------------
-- Es el boton "Quedaron de acuerdo". Puede pulsarlo cualquiera de los
-- dos capitanes: para ese punto ya lo hablaron en el chat, y exigir dos
-- confirmaciones agregaria un paso que nadie pidio.
--
-- Devuelve el reto ya cerrado, con match_id apuntando al partido nuevo.
create or replace function public.confirmar_acuerdo(p_challenge_id uuid)
returns public.challenges
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_reto  public.challenges;
  v_rival text;
  v_match uuid;
begin
  select * into v_reto from public.challenges where id = p_challenge_id;

  if v_reto.id is null then
    raise exception 'El reto no existe' using errcode = 'P0002';
  end if;

  if v_reto.status <> 'pending' then
    raise exception 'Este reto ya se cerró' using errcode = '23514';
  end if;

  if not (public.can_captain(v_reto.from_team_id)
          or public.can_captain(v_reto.to_team_id)) then
    raise exception 'Solo los capitanes pueden confirmar el acuerdo'
      using errcode = '42501';
  end if;

  if v_reto.proposed_kickoff_at <= now() then
    raise exception 'La fecha acordada ya pasó. Ajusten el horario primero.'
      using errcode = '23514';
  end if;

  -- Se revisa la agenda de los dos, no solo la de quien pulsa.
  if public.hay_conflicto_horario(
       v_reto.from_team_id, v_reto.proposed_kickoff_at,
       v_reto.duration_minutes, p_challenge_id) then
    raise exception 'El equipo retador ya tiene un partido a esa hora'
      using errcode = '23505';
  end if;

  if public.hay_conflicto_horario(
       v_reto.to_team_id, v_reto.proposed_kickoff_at,
       v_reto.duration_minutes, p_challenge_id) then
    raise exception 'El equipo retado ya tiene un partido a esa hora'
      using errcode = '23505';
  end if;

  select name into v_rival from public.teams where id = v_reto.to_team_id;

  -- El partido lo lleva quien reto (es su marcador). El retado queda
  -- como opponent_team_id, que es lo que le da acceso de lectura.
  insert into public.matches (
    team_id, opponent_team_id, opponent_name, kickoff_at, venue,
    duration_minutes, substitutions_allowed, status, is_home, created_by
  )
  values (
    v_reto.from_team_id, v_reto.to_team_id, v_rival,
    v_reto.proposed_kickoff_at, v_reto.venue,
    v_reto.duration_minutes, v_reto.substitutions_allowed,
    'scheduled', true, auth.uid()
  )
  returning id into v_match;

  -- Al salir de 'pending', el trigger de arriba borra el chat.
  update public.challenges
  set status       = 'accepted',
      match_id     = v_match,
      responded_by = auth.uid(),
      responded_at = now(),
      updated_at   = now()
  where id = p_challenge_id
  returning * into v_reto;

  return v_reto;
end;
$$;

grant execute on function public.confirmar_acuerdo(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 3. El cronograma
-- ---------------------------------------------------------------------
-- Solo partidos ya acordados. Un reto en negociacion NO aparece aca:
-- entra al cronograma recien cuando los capitanes confirman.
drop view if exists public.cronograma;
create view public.cronograma
with (security_invoker = true)
as
select
  m.id,
  m.team_id,
  m.opponent_team_id,
  m.opponent_name,
  m.kickoff_at,
  m.kickoff_at + make_interval(mins => m.duration_minutes) as termina_at,
  m.venue,
  m.competition,
  m.status,
  m.is_home,
  m.duration_minutes,
  m.substitutions_allowed,
  m.team_score,
  m.opponent_score,
  local.name  as club_local,
  visita.name as club_visitante,
  -- true si el rival tambien usa la app (partido acordado por reto).
  (m.opponent_team_id is not null) as rival_en_la_app
from public.matches m
join public.teams local on local.id = m.team_id
left join public.teams visita on visita.id = m.opponent_team_id
where m.status in ('scheduled', 'live');

comment on view public.cronograma is
  'Partidos agendados. Un reto entra aquí solo cuando los capitanes confirman.';

grant select on public.cronograma to anon, authenticated;

-- ---------------------------------------------------------------------
-- 4. Vencimiento de retos viejos
-- ---------------------------------------------------------------------
-- Un reto cuya fecha ya paso sin respuesta no deberia seguir abierto ni
-- conservando su chat. Se llama desde la app al abrir la bandeja.
create or replace function public.vencer_retos_pasados()
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_afectados int;
begin
  update public.challenges
  set status = 'expired', updated_at = now()
  where status = 'pending'
    and proposed_kickoff_at < now();

  get diagnostics v_afectados = row_count;
  return v_afectados;
end;
$$;

grant execute on function public.vencer_retos_pasados() to authenticated;
