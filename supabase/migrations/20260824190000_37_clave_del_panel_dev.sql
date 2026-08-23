-- =====================================================================
-- Anotar Gol - 37 | Clave para abrir el panel del dev
-- =====================================================================
-- Idea del 24/08/2026: una clave única para que el dev entre a su panel.
--
-- Hay dos formas de entender eso y solo una es segura:
--
--   A) La clave TE CONVIERTE en dev.
--      Sería un token al portador con poder total sobre la plataforma:
--      quien lo tenga puede borrar cualquier liga, leer cualquier chat y
--      editar cualquier equipo. Si se filtra en una captura o un mensaje,
--      nadie se entera. NO se implementa así.
--
--   B) Ya eres dev, y la clave ABRE el panel.
--      Segundo factor. Aunque alguien te tome el teléfono con la sesión
--      abierta, no llega al panel sin el código. Esto es lo que se hace.
--
-- Por eso `dev_abrir_panel` exige estar en `app_admins` ANTES de mirar
-- la clave: sin ser dev, ningún código sirve para nada.
--
-- Otras decisiones:
--   * Se guarda un hash bcrypt, no el código. Leer la base no revela la
--     clave.
--   * El panel se abre por un rato y se cierra solo. Un panel abierto
--     para siempre no es un segundo factor, es un trámite.
--   * Cinco intentos fallidos y se bloquea un rato, para que no se pueda
--     probar a fuerza bruta.
--   * Todo intento, acertado o no, queda en la bitácora del dev.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. La clave, hasheada
-- ---------------------------------------------------------------------
create table if not exists public.dev_panel_key (
  id         boolean primary key default true check (id),
  code_hash  text not null,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null
);

comment on table public.dev_panel_key is
  'Hash de la clave del panel. Una sola fila. No guarda el código en claro.';

alter table public.dev_panel_key enable row level security;

-- Nadie la lee desde la API, ni siquiera el dev: se compara por función.
drop policy if exists dev_panel_key_nadie on public.dev_panel_key;
create policy dev_panel_key_nadie on public.dev_panel_key
  for all to authenticated
  using (false) with check (false);

-- ---------------------------------------------------------------------
-- 2. Quién tiene el panel abierto
-- ---------------------------------------------------------------------
create table if not exists public.dev_panel_access (
  user_id          uuid primary key references auth.users (id) on delete cascade,
  expires_at       timestamptz,
  intentos         int not null default 0,
  bloqueado_hasta  timestamptz,
  ultimo_intento   timestamptz
);

alter table public.dev_panel_access enable row level security;

drop policy if exists dev_panel_access_propio on public.dev_panel_access;
create policy dev_panel_access_propio on public.dev_panel_access
  for select to authenticated
  using (user_id = auth.uid() and public.es_dev());

-- ---------------------------------------------------------------------
-- 3. ¿Está abierto?
-- ---------------------------------------------------------------------
create or replace function public.dev_panel_abierto()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.es_dev() and exists (
    select 1 from public.dev_panel_access a
    where a.user_id = auth.uid()
      and a.expires_at is not null
      and a.expires_at > now()
  );
$$;

grant execute on function public.dev_panel_abierto() to authenticated;

-- ---------------------------------------------------------------------
-- 4. Definir o cambiar la clave
-- ---------------------------------------------------------------------
-- La primera vez la puede poner cualquier dev. Después, hay que tener el
-- panel abierto para cambiarla: si no, quien te robe la sesión podría
-- cambiártela y dejarte fuera.
create or replace function public.dev_definir_clave(p_nueva text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp, extensions
as $$
declare
  v_existe boolean := exists (select 1 from public.dev_panel_key);
begin
  if not public.es_dev() then
    raise exception 'Solo la cuenta de desarrollo' using errcode = '42501';
  end if;

  if v_existe and not public.dev_panel_abierto() then
    raise exception 'Abre el panel antes de cambiar su clave'
      using errcode = '42501';
  end if;

  if p_nueva is null or char_length(btrim(p_nueva)) < 8 then
    raise exception 'La clave del panel necesita al menos 8 caracteres'
      using errcode = '23514';
  end if;

  insert into public.dev_panel_key (id, code_hash, updated_by)
  values (true, extensions.crypt(btrim(p_nueva), extensions.gen_salt('bf', 10)), auth.uid())
  on conflict (id) do update
    set code_hash = excluded.code_hash,
        updated_at = now(),
        updated_by = excluded.updated_by;

  perform public.registrar_accion_dev('definir_clave_panel', 'dev_panel_key', null, null);
end;
$$;

grant execute on function public.dev_definir_clave(text) to authenticated;

-- ---------------------------------------------------------------------
-- 5. Abrir el panel
-- ---------------------------------------------------------------------
create or replace function public.dev_abrir_panel(
  p_codigo  text,
  p_minutos int default 30
)
returns timestamptz
language plpgsql
security definer
set search_path = public, pg_temp, extensions
as $$
declare
  v_hash    text;
  v_acceso  public.dev_panel_access;
  v_hasta   timestamptz;
begin
  -- Ser dev es requisito PREVIO. La clave abre el panel, no reparte
  -- poderes: sin estar en app_admins ningún código sirve.
  if not public.es_dev() then
    raise exception 'Esta cuenta no tiene panel' using errcode = '42501';
  end if;

  select * into v_acceso from public.dev_panel_access where user_id = auth.uid();

  if v_acceso.bloqueado_hasta is not null and v_acceso.bloqueado_hasta > now() then
    raise exception 'Demasiados intentos. Vuelve a probar en % minutos.',
      ceil(extract(epoch from (v_acceso.bloqueado_hasta - now())) / 60)
      using errcode = '42501';
  end if;

  select code_hash into v_hash from public.dev_panel_key;

  if v_hash is null then
    raise exception 'Todavía no hay clave de panel'
      using errcode = 'P0002',
            hint = 'Defínela con dev_definir_clave().';
  end if;

  if extensions.crypt(btrim(coalesce(p_codigo, '')), v_hash) <> v_hash then
    insert into public.dev_panel_access (user_id, intentos, ultimo_intento)
    values (auth.uid(), 1, now())
    on conflict (user_id) do update
      set intentos = public.dev_panel_access.intentos + 1,
          ultimo_intento = now(),
          -- Cinco fallos seguidos y se cierra un cuarto de hora.
          bloqueado_hasta = case
            when public.dev_panel_access.intentos + 1 >= 5
            then now() + interval '15 minutes' else null end;

    perform public.registrar_accion_dev('panel_clave_incorrecta', null, null, null);

    raise exception 'Clave incorrecta' using errcode = '42501';
  end if;

  v_hasta := now() + make_interval(mins => least(greatest(p_minutos, 5), 120));

  insert into public.dev_panel_access (user_id, expires_at, intentos, ultimo_intento)
  values (auth.uid(), v_hasta, 0, now())
  on conflict (user_id) do update
    set expires_at = excluded.expires_at,
        intentos = 0,
        bloqueado_hasta = null,
        ultimo_intento = now();

  perform public.registrar_accion_dev(
    'panel_abierto', null, null, jsonb_build_object('hasta', v_hasta));

  return v_hasta;
end;
$$;

grant execute on function public.dev_abrir_panel(text, int) to authenticated;

create or replace function public.dev_cerrar_panel()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.dev_panel_access set expires_at = null where user_id = auth.uid();
  perform public.registrar_accion_dev('panel_cerrado', null, null, null);
end;
$$;

grant execute on function public.dev_cerrar_panel() to authenticated;

-- ---------------------------------------------------------------------
-- 6. El panel exige estar abierto
-- ---------------------------------------------------------------------
-- Ver todo sigue dependiendo de es_dev(): eso es la identidad. Lo que
-- pasa a exigir la clave es el PANEL y las acciones que se llevan cosas
-- por delante.
drop view if exists public.panel_dev_grupos;
create view public.panel_dev_grupos
with (security_invoker = true)
as
select
  g.id, g.name, g.slug, g.description, g.created_at,
  (select count(*) from public.teams t where t.group_id = g.id)           as equipos,
  (select count(*) from public.group_members gm where gm.group_id = g.id) as miembros,
  (select count(*) from public.group_invites gi
     where gi.group_id = g.id and gi.is_active)                           as invitaciones_activas,
  (select count(*) from public.matches m
     join public.teams t2 on t2.id = m.team_id
    where t2.group_id = g.id)                                             as partidos
from public.groups g
where public.dev_panel_abierto();

grant select on public.panel_dev_grupos to authenticated;

drop view if exists public.panel_dev_equipos;
create view public.panel_dev_equipos
with (security_invoker = true)
as
select
  t.id, t.group_id,
  g.name            as liga,
  t.numero_en_grupo as numero,
  t.name            as nombre,
  t.logo_url,
  public.etiqueta_equipo(t.numero_en_grupo, t.name, true) as etiqueta,
  t.plantilla_confirmada,
  public.equipo_habilitado(t.id) as habilitado,
  (select count(*) from public.players p
    where p.team_id = t.id and p.is_active)                         as jugadores,
  (select count(*) from public.players p
    where p.team_id = t.id and p.is_active and p.cedula is not null) as con_cedula,
  (select count(*) from public.team_members tm
    where tm.team_id = t.id)                                        as miembros,
  exists (select 1 from public.team_members tm
           where tm.team_id = t.id and tm.is_captain)               as tiene_capitan,
  t.created_at
from public.teams t
join public.groups g on g.id = t.group_id
where public.dev_panel_abierto()
order by g.name, t.numero_en_grupo;

grant select on public.panel_dev_equipos to authenticated;

-- ---------------------------------------------------------------------
-- 7. Lo que se lleva cosas por delante, también
-- ---------------------------------------------------------------------
create or replace function public.dev_borrar_grupo(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_nombre  text;
  v_equipos int;
begin
  if not public.dev_panel_abierto() then
    raise exception 'Abre el panel con tu clave antes de borrar una liga'
      using errcode = '42501';
  end if;

  select name into v_nombre from public.groups where id = p_group_id;
  if v_nombre is null then
    raise exception 'Ese grupo no existe' using errcode = 'P0002';
  end if;

  select count(*) into v_equipos from public.teams where group_id = p_group_id;

  perform public.registrar_accion_dev(
    'borrar_grupo', 'groups', p_group_id,
    jsonb_build_object('nombre', v_nombre, 'equipos_arrastrados', v_equipos));

  delete from public.groups where id = p_group_id;
end;
$$;

create or replace function public.dev_borrar_equipo(p_team_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_nombre text;
  v_jug    int;
begin
  if not public.dev_panel_abierto() then
    raise exception 'Abre el panel con tu clave antes de borrar un equipo'
      using errcode = '42501';
  end if;

  select name into v_nombre from public.teams where id = p_team_id;
  if v_nombre is null then
    raise exception 'Ese equipo no existe' using errcode = 'P0002';
  end if;

  select count(*) into v_jug from public.players where team_id = p_team_id;

  perform public.registrar_accion_dev(
    'borrar_equipo', 'teams', p_team_id,
    jsonb_build_object('nombre', v_nombre, 'jugadores', v_jug));

  delete from public.teams where id = p_team_id;
end;
$$;

grant execute on function public.dev_borrar_grupo(uuid)  to authenticated;
grant execute on function public.dev_borrar_equipo(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 8. Estado del panel, para la app
-- ---------------------------------------------------------------------
create or replace function public.mi_panel_dev()
returns table (
  soy_dev         boolean,
  hay_clave       boolean,
  abierto         boolean,
  expira_at       timestamptz,
  bloqueado_hasta timestamptz,
  intentos        int
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    public.es_dev(),
    exists (select 1 from public.dev_panel_key),
    public.dev_panel_abierto(),
    (select a.expires_at from public.dev_panel_access a where a.user_id = auth.uid()),
    (select a.bloqueado_hasta from public.dev_panel_access a where a.user_id = auth.uid()),
    coalesce((select a.intentos from public.dev_panel_access a where a.user_id = auth.uid()), 0);
$$;

grant execute on function public.mi_panel_dev() to authenticated;
