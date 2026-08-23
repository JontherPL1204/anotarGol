-- =====================================================================
-- Anotar Gol - 27 | Que el dev no deje rastro
-- =====================================================================
-- La migración 26 sacó al dev de las listas de miembros. Faltaba una
-- fuga más fina:
--
--   `groups.created_by` y `group_invites.created_by` guardaban su uuid,
--   y el administrador de la liga puede leer esas tablas. Vería un
--   identificador que no aparece en ningún listado de miembros y del que
--   no puede leer el perfil. De ahí a deducir "hay alguien más con
--   acceso" hay un paso.
--
-- Solución: en las columnas visibles no se guarda nada, y la trazabilidad
-- se mueve a una bitácora que solo el dev puede leer. No se pierde el
-- registro de quién hizo qué; deja de estar a la vista.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Bitácora privada
-- ---------------------------------------------------------------------
create table if not exists public.dev_audit (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users (id) on delete set null,
  accion      text not null,
  tabla       text,
  registro_id uuid,
  detalle     jsonb,
  created_at  timestamptz not null default now()
);

create index if not exists dev_audit_fecha_idx on public.dev_audit (created_at desc);

alter table public.dev_audit enable row level security;

drop policy if exists dev_audit_solo_dev on public.dev_audit;
create policy dev_audit_solo_dev on public.dev_audit
  for all to authenticated
  using (public.es_dev())
  with check (public.es_dev());

comment on table public.dev_audit is
  'Qué hizo la cuenta de desarrollo. Solo la lee un dev: mantiene la trazabilidad sin exponerla.';

create or replace function public.registrar_accion_dev(
  p_accion      text,
  p_tabla       text default null,
  p_registro_id uuid default null,
  p_detalle     jsonb default null
)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  insert into public.dev_audit (user_id, accion, tabla, registro_id, detalle)
  values (auth.uid(), p_accion, p_tabla, p_registro_id, p_detalle);
$$;

-- ---------------------------------------------------------------------
-- 2. Crear grupo sin firmar
-- ---------------------------------------------------------------------
create or replace function public.crear_grupo(
  p_nombre      text,
  p_descripcion text default null
)
returns public.groups
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_grupo public.groups;
  v_base  text;
  v_slug  text;
  v_n     int := 0;
  v_code  text;
begin
  if auth.uid() is null then
    raise exception 'Debes iniciar sesión' using errcode = '42501';
  end if;

  if not public.es_dev() then
    raise exception 'Solo la cuenta de desarrollo puede crear grupos'
      using errcode = '42501',
            hint = 'Pide una clave de invitación a quien administra el grupo.';
  end if;

  v_base := coalesce(nullif(public.slugify(p_nombre), ''), 'grupo');
  v_slug := v_base;
  while exists (select 1 from public.groups g where g.slug = v_slug) loop
    v_n := v_n + 1;
    v_slug := v_base || '-' || v_n;
  end loop;

  -- created_by queda en null: el dev no firma lo que crea. Quien mire la
  -- fila ve una liga sin autor, no una liga creada por un desconocido.
  insert into public.groups (name, slug, description, created_by)
  values (btrim(p_nombre), v_slug, p_descripcion, null)
  returning * into v_grupo;

  v_code := public.generar_codigo_invitacion();

  insert into public.group_invites (
    group_id, code, created_by, para_capitan, para_admin
  )
  values (v_grupo.id, v_code, null, true, true);

  perform public.registrar_accion_dev(
    'crear_grupo', 'groups', v_grupo.id,
    jsonb_build_object('nombre', v_grupo.name, 'clave_admin', v_code));

  return v_grupo;
end;
$$;

grant execute on function public.crear_grupo(text, text) to authenticated;

-- ---------------------------------------------------------------------
-- 3. Las invitaciones del dev tampoco llevan firma
-- ---------------------------------------------------------------------
create or replace function public.crear_invitacion(
  p_group_id     uuid,
  p_max_usos     int     default null,
  p_dias         int     default null,
  p_para_capitan boolean default false,
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

  insert into public.group_invites (
    group_id, code, created_by, max_uses, expires_at, para_capitan, para_admin
  )
  values (
    p_group_id,
    public.generar_codigo_invitacion(),
    case when v_es_dev then null else auth.uid() end,
    p_max_usos,
    case when p_dias is null then null else now() + make_interval(days => p_dias) end,
    coalesce(p_para_capitan, false) or coalesce(p_para_admin, false),
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
-- 4. Limpiar el rastro que ya existiera
-- ---------------------------------------------------------------------
update public.groups
set created_by = null
where created_by in (select user_id from public.app_admins);

update public.group_invites
set created_by = null
where created_by in (select user_id from public.app_admins);

update public.teams
set created_by = null
where created_by in (select user_id from public.app_admins);
