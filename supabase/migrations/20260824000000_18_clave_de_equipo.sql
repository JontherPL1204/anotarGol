-- =====================================================================
-- Anotar Gol - 18 | La segunda clave: entrar a un equipo
-- =====================================================================
-- Hay dos claves, y hacen cosas distintas:
--
--   CLAVE DE GRUPO   (login)  -> entras a la liga. Ves sus equipos, su
--                                cronograma, su tabla. La reparte el
--                                administrador del grupo.
--   CLAVE DE EQUIPO  (club)   -> te sumas a un equipo concreto de esa
--                                liga. La reparte el capitán.
--
-- Detalle de usabilidad que se resuelve aquí:
--   Si te dan la clave del equipo pero nadie te dio la del grupo, no
--   tiene sentido dejarte fuera: pertenecer a un equipo implica estar en
--   su liga. Así que canjear una clave de equipo también te mete en el
--   grupo, como miembro simple y SIN permiso para fundar equipos. La
--   clave es la autorización; pedir dos códigos para un solo acto sería
--   fricción sin ganancia de seguridad.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Generador de códigos compartido
-- ---------------------------------------------------------------------
-- Antes solo miraba `group_invites`. Con dos tablas de códigos hay que
-- comprobar las dos, o un día una clave de equipo chocaría con una de
-- grupo y el canje elegiría la equivocada.
create or replace function public.generar_codigo_invitacion()
returns text
language plpgsql
volatile
set search_path = public, pg_temp
as $$
declare
  v_alfabeto text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_codigo   text;
  v_intento  int := 0;
begin
  loop
    v_codigo := '';
    for i in 1..8 loop
      v_codigo := v_codigo ||
        substr(v_alfabeto, 1 + floor(random() * length(v_alfabeto))::int, 1);
    end loop;

    exit when not exists (select 1 from public.group_invites gi where gi.code = v_codigo)
          and not exists (select 1 from public.team_invites ti where ti.code = v_codigo);

    v_intento := v_intento + 1;
    if v_intento > 50 then
      raise exception 'No se pudo generar un código libre';
    end if;
  end loop;

  return v_codigo;
end;
$$;

-- ---------------------------------------------------------------------
-- 2. Claves de equipo
-- ---------------------------------------------------------------------
create table if not exists public.team_invites (
  id         uuid primary key default gen_random_uuid(),
  team_id    uuid not null references public.teams (id) on delete cascade,
  code       text not null unique,
  -- Con qué rol entra quien la canjee. Por defecto jugador: los roles de
  -- mando no se reparten por código.
  rol        public.team_role not null default 'player',
  created_by uuid references auth.users (id) on delete set null,
  max_uses   int,
  uses       int not null default 0,
  expires_at timestamptz,
  is_active  boolean not null default true,
  created_at timestamptz not null default now(),
  constraint team_invites_rol_chk check (rol in ('player', 'coach', 'viewer'))
);

create index if not exists team_invites_team_idx on public.team_invites (team_id);

comment on table public.team_invites is
  'Claves que reparte el capitán para que su gente se sume al equipo.';

alter table public.team_invites enable row level security;

-- Las ve y las crea quien manda en el club.
drop policy if exists team_invites_select on public.team_invites;
create policy team_invites_select on public.team_invites
  for select to authenticated
  using (public.can_captain(team_id) or public.can_admin_team(team_id));

drop policy if exists team_invites_write on public.team_invites;
create policy team_invites_write on public.team_invites
  for all to authenticated
  using (public.can_captain(team_id) or public.can_admin_team(team_id))
  with check (public.can_captain(team_id) or public.can_admin_team(team_id));

-- ---------------------------------------------------------------------
-- 3. Crear la clave del equipo
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

  if p_rol not in ('player', 'coach', 'viewer') then
    raise exception 'Por código solo se entra como jugador, cuerpo técnico o hincha'
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

-- ---------------------------------------------------------------------
-- 4. Canjear la clave del equipo
-- ---------------------------------------------------------------------
create or replace function public.unirse_a_equipo_con_codigo(p_codigo text)
returns public.teams
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_inv    public.team_invites;
  v_equipo public.teams;
begin
  if auth.uid() is null then
    raise exception 'Debes iniciar sesión' using errcode = '42501';
  end if;

  select * into v_inv
  from public.team_invites
  where upper(btrim(code)) = upper(btrim(p_codigo));

  if v_inv.id is null then
    raise exception 'Esa clave de equipo no existe' using errcode = 'P0002';
  end if;

  if not v_inv.is_active then
    raise exception 'Esa clave fue desactivada' using errcode = '42501';
  end if;

  if v_inv.expires_at is not null and v_inv.expires_at < now() then
    raise exception 'Esa clave ya venció' using errcode = '42501';
  end if;

  if v_inv.max_uses is not null and v_inv.uses >= v_inv.max_uses then
    raise exception 'Esa clave ya se usó el máximo de veces' using errcode = '42501';
  end if;

  select * into v_equipo from public.teams where id = v_inv.team_id;

  -- Pertenecer al equipo implica estar en su liga: si falta, se entra
  -- como miembro simple, sin permiso para fundar equipos.
  if v_equipo.group_id is not null
     and not exists (
       select 1 from public.group_members
       where group_id = v_equipo.group_id and user_id = auth.uid()
     ) then
    insert into public.group_members (group_id, user_id, role, puede_fundar_equipo)
    values (v_equipo.group_id, auth.uid(), 'member', false);
  end if;

  -- Ya estabas en el equipo: no se gasta un uso ni se toca tu rol, para
  -- que un jugador que ya es capitán no se degrade al reusar la clave.
  if exists (
    select 1 from public.team_members
    where team_id = v_inv.team_id and user_id = auth.uid()
  ) then
    return v_equipo;
  end if;

  insert into public.team_members (team_id, user_id, role)
  values (v_inv.team_id, auth.uid(), v_inv.rol);

  update public.team_invites set uses = uses + 1 where id = v_inv.id;

  return v_equipo;
end;
$$;

grant execute on function public.crear_invitacion_equipo(uuid, public.team_role, int, int)
  to authenticated;
grant execute on function public.unirse_a_equipo_con_codigo(text) to authenticated;

-- ---------------------------------------------------------------------
-- 5. Canje único: la app no tiene por qué saber qué tipo de clave es
-- ---------------------------------------------------------------------
-- Quien recibe un código por WhatsApp no sabe si es de grupo o de
-- equipo. Esta función lo averigua y hace lo que corresponda.
create or replace function public.canjear_clave(p_codigo text)
returns table (
  tipo       text,
  group_id   uuid,
  group_name text,
  team_id    uuid,
  team_name  text
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_codigo text := upper(btrim(p_codigo));
  v_grupo  public.groups;
  v_equipo public.teams;
begin
  if exists (select 1 from public.group_invites where upper(btrim(code)) = v_codigo) then
    v_grupo := public.unirse_con_codigo(v_codigo);
    return query select 'grupo'::text, v_grupo.id, v_grupo.name, null::uuid, null::text;
    return;
  end if;

  if exists (select 1 from public.team_invites where upper(btrim(code)) = v_codigo) then
    v_equipo := public.unirse_a_equipo_con_codigo(v_codigo);
    select * into v_grupo from public.groups where id = v_equipo.group_id;
    return query select 'equipo'::text, v_grupo.id, v_grupo.name, v_equipo.id, v_equipo.name;
    return;
  end if;

  raise exception 'Esa clave no existe. Revísala con quien te la envió.'
    using errcode = 'P0002';
end;
$$;

grant execute on function public.canjear_clave(text) to authenticated;

comment on function public.canjear_clave is
  'Canjea una clave sin que el usuario tenga que saber si es de grupo o de equipo.';
