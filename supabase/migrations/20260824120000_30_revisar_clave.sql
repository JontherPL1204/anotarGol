-- =====================================================================
-- Anotar Gol - 30 | Saber qué es una clave antes de canjearla
-- =====================================================================
-- El flujo de entrada es: cédula + clave de invitación, y el sistema
-- decide solo qué hacer con esa clave. Pero `canjear_clave()` la consume
-- y recién ahí uno se entera de qué era.
--
-- Eso está mal para quien la escribe: tiene que ver ANTES qué le va a
-- pasar. No es lo mismo "esta clave te hace capitán de la Liga Norte y
-- vas a poder fundar tu equipo" que "esta clave te suma a Halcones FC
-- como jugador".
--
-- `revisar_clave()` lo dice sin gastar un uso.
--
-- Sobre exponer el nombre de la liga a quien tiene el código: el código
-- son 8 caracteres de un alfabeto de 32, o sea del orden de 10^12
-- combinaciones. Adivinarlo no es una vía practicable, y quien lo tiene
-- es porque alguien se lo dio.
-- =====================================================================

create or replace function public.revisar_clave(p_codigo text)
returns table (
  valida       boolean,
  motivo       text,     -- por qué no sirve, si no sirve
  tipo         text,     -- 'admin' | 'capitan' | 'jugador' | 'equipo'
  descripcion  text,     -- qué le va a pasar a quien la canjee
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
  v_c   text := upper(btrim(coalesce(p_codigo, '')));
  gi    public.group_invites;
  ti    public.team_invites;
  v_g   public.groups;
  v_t   public.teams;
begin
  if char_length(v_c) < 4 then
    return query select false, 'La clave son 8 caracteres.'::text,
      null::text, null::text, null::uuid, null::text, null::uuid, null::text, null::text;
    return;
  end if;

  -- ¿Clave de grupo?
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
      case when gi.para_admin then 'admin'
           when gi.para_capitan then 'capitan'
           else 'jugador' end,
      case when gi.para_admin then
             format('Vas a administrar la liga %s.', v_g.name)
           when gi.para_capitan then
             format('Entras a %s y podrás fundar tu equipo.', v_g.name)
           else
             format('Entras a %s. Para jugar, tu capitán tiene que ficharte.', v_g.name)
      end,
      v_g.id, v_g.name, null::uuid, null::text, null::text;
    return;
  end if;

  -- ¿Clave de equipo?
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
             case ti.rol
               when 'player' then 'jugador'
               when 'coach'  then 'cuerpo técnico'
               else 'hincha'
             end),
      v_g.id, v_g.name, v_t.id, v_t.name, ti.rol::text;
    return;
  end if;

  return query select false, 'Esa clave no existe. Revísala con quien te la envió.'::text,
    null::text, null::text, null::uuid, null::text, null::uuid, null::text, null::text;
end;
$$;

grant execute on function public.revisar_clave(text) to anon, authenticated;

comment on function public.revisar_clave is
  'Dice qué hace una clave sin consumirla, para poder confirmarlo antes de canjear.';

-- ---------------------------------------------------------------------
-- Canjear devolviendo también qué pasó
-- ---------------------------------------------------------------------
-- La app necesita saber a dónde llevar al usuario después: a fundar su
-- equipo, o directo al equipo al que acaba de entrar.
--
-- Se suelta primero: `create or replace` no puede cambiar el tipo de
-- retorno de una función que ya existe, y esta gana una columna.
drop function if exists public.canjear_clave(text);

create or replace function public.canjear_clave(p_codigo text)
returns table (
  tipo         text,
  group_id     uuid,
  group_name   text,
  team_id      uuid,
  team_name    text,
  puede_fundar boolean
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_codigo text := upper(btrim(p_codigo));
  v_grupo  public.groups;
  v_equipo public.teams;
  v_funda  boolean := false;
begin
  if exists (select 1 from public.group_invites where upper(btrim(code)) = v_codigo) then
    v_grupo := public.unirse_con_codigo(v_codigo);

    select gm.puede_fundar_equipo into v_funda
    from public.group_members gm
    where gm.group_id = v_grupo.id and gm.user_id = auth.uid();

    return query select 'grupo'::text, v_grupo.id, v_grupo.name,
      null::uuid, null::text, coalesce(v_funda, false);
    return;
  end if;

  if exists (select 1 from public.team_invites where upper(btrim(code)) = v_codigo) then
    v_equipo := public.unirse_a_equipo_con_codigo(v_codigo);
    select * into v_grupo from public.groups where id = v_equipo.group_id;

    select gm.puede_fundar_equipo into v_funda
    from public.group_members gm
    where gm.group_id = v_equipo.group_id and gm.user_id = auth.uid();

    return query select 'equipo'::text, v_grupo.id, v_grupo.name,
      v_equipo.id, v_equipo.name, coalesce(v_funda, false);
    return;
  end if;

  raise exception 'Esa clave no existe. Revísala con quien te la envió.'
    using errcode = 'P0002';
end;
$$;

grant execute on function public.canjear_clave(text) to authenticated;

-- ---------------------------------------------------------------------
-- Dónde quedó parado el usuario
-- ---------------------------------------------------------------------
-- Después de registrarse con cédula y canjear su clave, la app necesita
-- una sola respuesta: ¿a dónde lo llevo?
create or replace function public.mi_situacion()
returns table (
  tiene_grupo     boolean,
  tiene_equipo    boolean,
  puede_fundar    boolean,
  group_id        uuid,
  grupo           text,
  team_id         uuid,
  equipo          text,
  soy_capitan     boolean,
  tengo_cedula    boolean
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with mi_ficha as (
    select tm.team_id, t.name as equipo, t.group_id, tm.is_captain
    from public.team_members tm
    join public.teams t on t.id = tm.team_id
    where tm.user_id = auth.uid()
    order by tm.created_at
    limit 1
  ),
  mi_grupo as (
    select gm.group_id, g.name, gm.puede_fundar_equipo
    from public.group_members gm
    join public.groups g on g.id = gm.group_id
    where gm.user_id = auth.uid()
    order by gm.joined_at
    limit 1
  )
  select
    (select count(*) from public.group_members where user_id = auth.uid()) > 0,
    (select count(*) from public.team_members  where user_id = auth.uid()) > 0,
    coalesce((select puede_fundar_equipo from mi_grupo), false),
    coalesce((select group_id from mi_ficha), (select group_id from mi_grupo)),
    coalesce((select g.name from public.groups g
               where g.id = (select group_id from mi_ficha)),
             (select name from mi_grupo)),
    (select team_id from mi_ficha),
    (select equipo from mi_ficha),
    coalesce((select is_captain from mi_ficha), false),
    (select cedula is not null from public.profiles where id = auth.uid());
$$;

grant execute on function public.mi_situacion() to authenticated;

comment on function public.mi_situacion is
  'Una sola respuesta para que la app sepa a qué pantalla llevar al usuario.';
