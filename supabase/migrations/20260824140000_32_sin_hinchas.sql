-- =====================================================================
-- Anotar Gol - 32 | Por ahora solo hay dev, capitanes y jugadores
-- =====================================================================
-- No existe la figura del hincha. Eso cambia dos cosas:
--
--   * Toda clave de LIGA es de capitán. La variante "entras a la liga
--     pero no fundas nada" no tiene a quién servir: si no eres capitán,
--     entras por la clave de tu equipo.
--   * En un EQUIPO se entra como jugador o como cuerpo técnico.
--     'viewer' deja de repartirse.
--
-- El valor `viewer` del enum se conserva: quitarlo es destructivo y no
-- cuesta nada dejarlo por si más adelante se abre la app a espectadores.
-- Lo que cambia es que ya no se entrega.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Las claves de liga son de capitán
-- ---------------------------------------------------------------------
create or replace function public.crear_invitacion(
  p_group_id     uuid,
  p_max_usos     int     default null,
  p_dias         int     default null,
  p_para_capitan boolean default true,
  p_para_admin   boolean default false
)
returns public.group_invites
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_inv    public.group_invites;
  v_es_dev boolean := public.es_dev();
begin
  if not public.es_admin_del_grupo(p_group_id) then
    raise exception 'Solo un administrador del grupo puede crear invitaciones'
      using errcode = '42501';
  end if;

  if p_para_admin and not (v_es_dev or public.es_admin_del_grupo(p_group_id)) then
    raise exception 'No puedes crear claves de administrador' using errcode = '42501';
  end if;

  -- Sin hinchas, una clave de liga que no habilite a fundar equipo no le
  -- serviría a nadie: quien no es capitán entra por la de su equipo.
  if not coalesce(p_para_capitan, true) and not coalesce(p_para_admin, false) then
    raise exception 'Las claves de liga son para capitanes'
      using errcode = '23514',
            hint = 'Un jugador entra con la clave de su equipo, no con la de la liga.';
  end if;

  insert into public.group_invites (
    group_id, code, created_by, max_uses, expires_at, para_capitan, para_admin
  )
  values (
    p_group_id,
    public.generar_codigo_invitacion(),
    case when v_es_dev then null else auth.uid() end,
    p_max_usos,
    case when p_dias is null then null else now() + make_interval(days => p_dias) end,
    true,
    coalesce(p_para_admin, false)
  )
  returning * into v_inv;

  if v_es_dev then
    perform public.registrar_accion_dev(
      'crear_invitacion', 'group_invites', v_inv.id,
      jsonb_build_object('grupo', p_group_id, 'para_admin', p_para_admin));
  end if;

  return v_inv;
end;
$$;

grant execute on function public.crear_invitacion(uuid, int, int, boolean, boolean)
  to authenticated;

-- ---------------------------------------------------------------------
-- 2. En un equipo se entra a jugar o a dirigir
-- ---------------------------------------------------------------------
create or replace function public.crear_invitacion_equipo(
  p_team_id  uuid,
  p_rol      public.team_role default 'player',
  p_max_usos int default null,
  p_dias     int default null
)
returns public.team_invites
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_inv public.team_invites;
begin
  if not (public.can_captain(p_team_id) or public.can_admin_team(p_team_id)) then
    raise exception 'Solo el capitán o un administrador del club pueden crear claves'
      using errcode = '42501';
  end if;

  if p_rol not in ('player', 'coach') then
    raise exception 'Por código se entra como jugador o como cuerpo técnico'
      using errcode = '23514',
            hint = 'Los roles de mando se otorgan a mano desde la gestión del club.';
  end if;

  insert into public.team_invites (
    team_id, code, rol, created_by, max_uses, expires_at
  )
  values (
    p_team_id,
    public.generar_codigo_invitacion(),
    p_rol,
    auth.uid(),
    p_max_usos,
    case when p_dias is null then null else now() + make_interval(days => p_dias) end
  )
  returning * into v_inv;

  return v_inv;
end;
$$;

grant execute on function public.crear_invitacion_equipo(uuid, public.team_role, int, int)
  to authenticated;

-- ---------------------------------------------------------------------
-- 3. Los textos que ve quien escribe la clave
-- ---------------------------------------------------------------------
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
  if char_length(v_c) < 4 then
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

grant execute on function public.revisar_clave(text) to anon, authenticated;
