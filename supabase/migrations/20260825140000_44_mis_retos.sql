-- =====================================================================
-- Anotar Gol - 44 | Los retos, vistos desde los dos lados
-- =====================================================================
-- Ya existia `retos_recibidos`, pero un capitan tambien necesita ver los
-- que mandó: si no, reta a alguien y la pantalla se queda muda hasta que
-- le respondan. Sin eso vuelve a retar, y quedan dos retos iguales.
--
-- Se devuelve una sola lista con `soy_retador` en vez de dos consultas,
-- porque en la pantalla es una sola conversación: "Clásicos FC te retó"
-- y "retaste a Clásicos FC" son la misma fila mirada al revés.
--
-- El aviso de choque de horario solo se calcula para lo recibido. Para
-- lo enviado no aplica: el conflicto ya se comprobó al crear el reto, y
-- volver a mirarlo desde este lado diría siempre que choca consigo
-- mismo.
-- =====================================================================

create or replace function public.mis_retos(p_team_id uuid)
returns table (
  id                   uuid,
  soy_retador          boolean,
  otro_equipo_id       uuid,
  otro_equipo          text,
  otro_logo            text,
  status               text,
  message              text,
  proposed_kickoff_at  timestamptz,
  venue                text,
  duration_minutes     int,
  substitutions_allowed int,
  match_id             uuid,
  created_at           timestamptz,
  choca_con_tu_agenda  boolean
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    c.id,
    (c.from_team_id = p_team_id)                              as soy_retador,
    case when c.from_team_id = p_team_id
         then c.to_team_id else c.from_team_id end            as otro_equipo_id,
    -- Para el dev sale con su número delante; para el resto, el nombre
    -- a secas. Es la misma etiqueta que en el resto de la app.
    public.etiqueta_equipo(t.numero_en_grupo, t.name, public.es_dev())
                                                              as otro_equipo,
    t.logo_url                                                as otro_logo,
    c.status::text,
    c.message,
    c.proposed_kickoff_at,
    c.venue,
    c.duration_minutes,
    c.substitutions_allowed,
    c.match_id,
    c.created_at,
    case when c.from_team_id = p_team_id then false
         else public.hay_conflicto_horario(
                p_team_id, c.proposed_kickoff_at, c.duration_minutes, c.id)
    end                                                       as choca_con_tu_agenda
  from public.challenges c
  join public.teams t
    on t.id = case when c.from_team_id = p_team_id
                   then c.to_team_id else c.from_team_id end
  where (c.from_team_id = p_team_id or c.to_team_id = p_team_id)
    -- SECURITY DEFINER se salta las políticas, así que la pertenencia se
    -- comprueba aquí a mano. Sin esto, cualquiera podría leer los retos
    -- de un equipo ajeno pasando su id.
    and (public.is_team_member(p_team_id) or public.es_dev())
  order by
    (c.status = 'pending') desc,
    c.proposed_kickoff_at;
$$;

revoke all on function public.mis_retos(uuid) from public;
grant execute on function public.mis_retos(uuid) to authenticated;

comment on function public.mis_retos is
  'Retos de un equipo, enviados y recibidos, con soy_retador para distinguirlos.';
