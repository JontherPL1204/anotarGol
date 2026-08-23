-- =====================================================================
-- Anotar Gol - 42 | revisar_clave solo responde por invitaciones
-- =====================================================================
-- Hay una sola casilla para escribir la clave y la app decide sola de
-- qué tipo es. Las dos formas no se pueden confundir porque el largo ya
-- las separa:
--
--   * Invitación de liga o de equipo: 8 caracteres del alfabeto
--     ABCDEFGHJKLMNPQRSTUVWXYZ23456789. Sin O/0 ni I/1, para poder
--     dictarlas en voz alta. Se quedan exactamente como estaban.
--   * Clave de acceso de dev: 12 dígitos. crear_clave_dev ya exige 12
--     caracteres como mínimo, así que no hace falta cambiarla.
--
-- Lo único que se corrige aquí es del lado del servidor. revisar_clave
-- es la única función que anon puede ejecutar, para que el registro
-- sepa a qué liga lleva un código antes de que exista la cuenta. Su
-- guarda era `char_length < 4`, así que respondía por cualquier cosa de
-- cuatro caracteres en adelante —incluidos doce dígitos—. Eso la volvía
-- un oráculo para adivinar la clave de dev sin sesión y sin que el
-- contador de intentos se enterara.
--
-- Ahora solo contesta por algo con forma de invitación. La app ya no la
-- llama con una clave de dev, pero la defensa no puede depender de que
-- el cliente se porte bien.
-- =====================================================================

create or replace function public.revisar_clave(p_codigo text)
returns table (
  valida       boolean,
  motivo       text,
  tipo         text,
  descripcion  text,
  group_id     uuid,
  grupo        text,
  team_id      uuid,
  equipo       text,
  rol_equipo   text
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_c text := upper(btrim(coalesce(p_codigo, '')));
  gi  public.group_invites;
  ti  public.team_invites;
  v_g public.groups;
  v_t public.teams;
begin
  -- Solo se responde por algo con forma de invitación: ocho caracteres
  -- del alfabeto. Una clave de dev son doce dígitos, y contestar por
  -- ella convertiría a esta función —la única que anon puede ejecutar—
  -- en un oráculo de fuerza bruta sin sesión y sin contador.
  if v_c !~ '^[A-HJ-NP-Z2-9]{8}$' then
    return query select false, 'La clave son 8 caracteres.'::text,
      null::text, null::text, null::uuid, null::text, null::uuid, null::text, null::text;
    return;
  end if;

  select * into gi from public.group_invites where upper(btrim(code)) = v_c;

  if gi.id is not null then
    select * into v_g from public.groups where id = gi.group_id;

    if not gi.is_active then
      return query select false, 'Esa invitación fue desactivada.'::text,
        null::text, null::text, v_g.id, v_g.name, null::uuid, null::text, null::text;
      return;
    end if;
    if gi.expires_at is not null and gi.expires_at < now() then
      return query select false, 'Esa invitación ya venció.'::text,
        null::text, null::text, v_g.id, v_g.name, null::uuid, null::text, null::text;
      return;
    end if;
    if gi.max_uses is not null and gi.uses >= gi.max_uses then
      return query select false, 'Esa invitación ya se usó el máximo de veces.'::text,
        null::text, null::text, v_g.id, v_g.name, null::uuid, null::text, null::text;
      return;
    end if;

    return query select
      true,
      null::text,
      case when gi.para_admin then 'admin' else 'capitan' end,
      case when gi.para_admin then
             format('Vas a administrar la liga %s.', v_g.name)
           else
             format('Entras a %s como capitán y podrás fundar tu equipo.', v_g.name)
      end,
      v_g.id, v_g.name, null::uuid, null::text, null::text;
    return;
  end if;

  select * into ti from public.team_invites where upper(btrim(code)) = v_c;

  if ti.id is not null then
    select * into v_t from public.teams where id = ti.team_id;
    select * into v_g from public.groups where id = v_t.group_id;

    if not ti.is_active then
      return query select false, 'Esa clave fue desactivada.'::text,
        null::text, null::text, v_g.id, v_g.name, v_t.id, v_t.name, null::text;
      return;
    end if;
    if ti.expires_at is not null and ti.expires_at < now() then
      return query select false, 'Esa clave ya venció.'::text,
        null::text, null::text, v_g.id, v_g.name, v_t.id, v_t.name, null::text;
      return;
    end if;
    if ti.max_uses is not null and ti.uses >= ti.max_uses then
      return query select false, 'Esa clave ya se usó el máximo de veces.'::text,
        null::text, null::text, v_g.id, v_g.name, v_t.id, v_t.name, null::text;
      return;
    end if;

    return query select
      true,
      null::text,
      'equipo'::text,
      format('Te sumas a %s como %s.',
             v_t.name,
             case ti.rol when 'coach' then 'cuerpo técnico' else 'jugador' end),
      v_g.id, v_g.name, v_t.id, v_t.name, ti.rol::text;
    return;
  end if;

  return query select false, 'Esa clave no existe. Revísala con quien te la envió.'::text,
    null::text, null::text, null::uuid, null::text, null::uuid, null::text, null::text;
end;
$$;

revoke all on function public.revisar_clave(text) from public;
grant execute on function public.revisar_clave(text) to authenticated, anon;

comment on function public.revisar_clave is
  'Dice qué hace una clave de invitación sin consumirla. No responde por '
  'claves de dev: sería un oráculo de fuerza bruta sin sesión.';
