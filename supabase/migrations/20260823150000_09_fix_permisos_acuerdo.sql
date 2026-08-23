-- =====================================================================
-- Anotar Gol - 09 | Corrección: quien crea el partido acordado
-- =====================================================================
-- Bug encontrado al probar el flujo completo contra la base real.
--
-- Sintoma:
--   El capitán del equipo RETADO pulsa "Quedaron de acuerdo" y falla con
--   "new row violates row-level security policy for table matches".
--
-- Causa:
--   El partido se crea a nombre del equipo RETADOR (es su marcador),
--   pero `confirmar_acuerdo` corria con los permisos de quien la llama.
--   La politica de insercion de `matches` exige `can_edit_team(team_id)`,
--   y el capitán retado no es miembro del club retador. RLS hacia bien
--   su trabajo; la funcion estaba mal planteada.
--
-- Arreglo:
--   Las dos funciones que cierran un reto pasan a SECURITY DEFINER. La
--   autorizacion no desaparece: la hace la propia funcion, que exige ser
--   capitán de uno de los dos equipos y solo puede crear un partido
--   entre esos dos. Es el patron correcto para una operacion que cruza
--   la frontera de dos clubes.
--
-- Alternativa descartada: aflojar la politica de `matches` para permitir
-- insertar en nombre de otro club. Eso abriria un agujero para todo el
-- mundo, no solo para este flujo.
-- =====================================================================

create or replace function public.confirmar_acuerdo(p_challenge_id uuid)
returns public.challenges
language plpgsql
security definer
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

  -- La autorizacion vive aqui, no en RLS: sin esto, SECURITY DEFINER
  -- dejaria que cualquiera cerrara retos ajenos.
  if not (public.can_captain(v_reto.from_team_id)
          or public.can_captain(v_reto.to_team_id)) then
    raise exception 'Solo los capitanes pueden confirmar el acuerdo'
      using errcode = '42501';
  end if;

  if v_reto.proposed_kickoff_at <= now() then
    raise exception 'La fecha acordada ya pasó. Ajusten el horario primero.'
      using errcode = '23514';
  end if;

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

  -- Al salir de 'pending', el trigger borra el chat temporal.
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

-- Mismo problema en responder_reto cuando se acepta.
create or replace function public.responder_reto(
  p_challenge_id uuid,
  p_aceptar      boolean
)
returns public.challenges
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_reto public.challenges;
begin
  select * into v_reto from public.challenges where id = p_challenge_id;

  if v_reto.id is null then
    raise exception 'El reto no existe' using errcode = 'P0002';
  end if;

  if v_reto.status <> 'pending' then
    raise exception 'Este reto ya fue respondido' using errcode = '23514';
  end if;

  -- Rechazar es potestad del equipo retado.
  if not public.can_captain(v_reto.to_team_id) then
    raise exception 'Solo el capitán del equipo retado puede responder'
      using errcode = '42501';
  end if;

  if p_aceptar then
    -- Aceptar es exactamente "quedaron de acuerdo": un solo camino, para
    -- que el chat se borre y el partido se registre siempre igual.
    return public.confirmar_acuerdo(p_challenge_id);
  end if;

  update public.challenges
  set status = 'rejected', responded_by = auth.uid(), responded_at = now(),
      updated_at = now()
  where id = p_challenge_id
  returning * into v_reto;

  return v_reto;
end;
$$;

grant execute on function public.confirmar_acuerdo(uuid) to authenticated;
grant execute on function public.responder_reto(uuid, boolean) to authenticated;
