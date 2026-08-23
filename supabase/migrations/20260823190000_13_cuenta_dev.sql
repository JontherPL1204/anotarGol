-- =====================================================================
-- Anotar Gol - 13 | Cuenta de desarrollador (superadministrador)
-- =====================================================================
-- Requisito del 23/08/2026:
--
--   Existe una cuenta de dev que puede ver y editar TODOS los grupos y
--   equipos, y que es la UNICA que puede crear un grupo nuevo. El resto
--   de la gente solo entra con clave de invitacion.
--
-- Como se concede:
--   No hay forma de volverse dev desde la app. Se inserta a mano en la
--   base, que es justo lo que se espera de un superadministrador:
--
--     insert into public.app_admins (user_id, note)
--     values ('<uuid del usuario>', 'cuenta de desarrollo');
--
--   Para saber el uuid: select id, email from auth.users where email = '...';
--
-- Por que se hace con una tabla y no con una columna en `profiles`:
--   `profiles` lo puede actualizar su dueño (politica profiles_update_self).
--   Una bandera ahi seria auto-otorgable. Esta tabla, en cambio, solo la
--   escribe alguien que ya es dev, o el equipo desde el panel de Supabase.
-- =====================================================================

create table if not exists public.app_admins (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  note       text,
  created_at timestamptz not null default now()
);

comment on table public.app_admins is
  'Cuentas con poder sobre toda la plataforma. Se otorga solo desde la base.';

alter table public.app_admins enable row level security;

create or replace function public.es_dev()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.app_admins a where a.user_id = auth.uid()
  );
$$;

grant execute on function public.es_dev() to authenticated;

-- Solo un dev ve y toca la lista de devs.
drop policy if exists app_admins_select on public.app_admins;
create policy app_admins_select on public.app_admins
  for select to authenticated using (public.es_dev());

drop policy if exists app_admins_write on public.app_admins;
create policy app_admins_write on public.app_admins
  for all to authenticated
  using (public.es_dev())
  with check (public.es_dev());

-- ---------------------------------------------------------------------
-- El poder del dev se inyecta en las funciones de permisos
-- ---------------------------------------------------------------------
-- Se toca aqui y no politica por politica: estas funciones son el unico
-- punto por el que pasa todo el modelo de acceso, asi que una linea en
-- cada una cubre las 60 y pico politicas sin repetir la condicion.

create or replace function public.es_miembro_del_grupo(p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.es_dev() or exists (
    select 1 from public.group_members gm
    where gm.group_id = p_group_id and gm.user_id = auth.uid()
  );
$$;

create or replace function public.es_admin_del_grupo(p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.es_dev() or exists (
    select 1 from public.group_members gm
    where gm.group_id = p_group_id
      and gm.user_id = auth.uid()
      and gm.role = 'group_admin'
  );
$$;

create or replace function public.can_view_team(p_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.es_dev() or exists (
    select 1
    from public.teams t
    where t.id = p_team_id
      and (
        public.is_team_member(t.id)
        or (t.group_id is not null and public.es_miembro_del_grupo(t.group_id))
        or (t.group_id is null and t.is_public)
      )
  );
$$;

create or replace function public.can_edit_team(p_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.es_dev()
      or coalesce(public.team_role_of(p_team_id) in ('owner', 'admin', 'coach'), false);
$$;

create or replace function public.can_admin_team(p_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.es_dev()
      or coalesce(public.team_role_of(p_team_id) in ('owner', 'admin'), false);
$$;

create or replace function public.can_edit_squad(p_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.es_dev()
      or coalesce(
           public.team_role_of(p_team_id) in ('owner', 'admin', 'coach', 'player'),
           false);
$$;

create or replace function public.can_captain(p_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.es_dev() or exists (
    select 1
    from public.team_members tm
    where tm.team_id = p_team_id
      and tm.user_id = auth.uid()
      and (tm.is_captain or tm.role in ('owner', 'admin'))
  );
$$;

-- ---------------------------------------------------------------------
-- Politicas que consultan la membresia directamente
-- ---------------------------------------------------------------------
-- `is_team_member` se deja literal a proposito ("soy miembro de verdad"),
-- asi que las politicas que la usan sin pasar por las funciones de
-- arriba necesitan su propia mencion al dev.

drop policy if exists teams_select on public.teams;
create policy teams_select on public.teams
  for select to anon, authenticated
  using (
    public.es_dev()
    or public.is_team_member(id)
    or (group_id is not null
        and is_discoverable
        and public.es_miembro_del_grupo(group_id))
    or (group_id is null and is_public)
  );

drop policy if exists team_members_select on public.team_members;
create policy team_members_select on public.team_members
  for select to authenticated
  using (public.es_dev() or public.is_team_member(team_id));

drop policy if exists challenges_select on public.challenges;
create policy challenges_select on public.challenges
  for select to authenticated
  using (
    public.es_dev()
    or public.is_team_member(from_team_id)
    or public.is_team_member(to_team_id)
  );

-- El chat interno se abre al dev SOLO para moderar. Las dos tiendas
-- exigen poder atender denuncias de contenido en apps con chat; sin un
-- camino para revisarlo, esa exigencia no se puede cumplir.
drop policy if exists team_messages_select on public.team_messages;
create policy team_messages_select on public.team_messages
  for select to authenticated
  using (public.es_dev() or public.is_team_member(team_id));

drop policy if exists team_messages_delete on public.team_messages;
create policy team_messages_delete on public.team_messages
  for delete to authenticated
  using (public.es_dev() or user_id = auth.uid() or public.can_admin_team(team_id));

-- ---------------------------------------------------------------------
-- Crear grupos queda reservado al dev
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

  insert into public.groups (name, slug, description, created_by)
  values (btrim(p_nombre), v_slug, p_descripcion, auth.uid())
  returning * into v_grupo;

  insert into public.group_members (group_id, user_id, role)
  values (v_grupo.id, auth.uid(), 'group_admin');

  insert into public.group_invites (group_id, code, created_by)
  values (v_grupo.id, public.generar_codigo_invitacion(), auth.uid());

  return v_grupo;
end;
$$;

-- Nadie inserta grupos por la puerta de atras saltandose el RPC.
drop policy if exists groups_insert on public.groups;
create policy groups_insert on public.groups
  for insert to authenticated
  with check (public.es_dev());

grant execute on function public.crear_grupo(text, text) to authenticated;

-- ---------------------------------------------------------------------
-- Panel del dev
-- ---------------------------------------------------------------------
-- Todos los grupos con su tamaño, para la pantalla de administracion.
-- La vista es security_invoker: a quien no sea dev le devuelve vacio,
-- porque groups_select ya lo filtra.
drop view if exists public.panel_dev_grupos;
create view public.panel_dev_grupos
with (security_invoker = true)
as
select
  g.id,
  g.name,
  g.slug,
  g.description,
  g.created_at,
  (select count(*) from public.teams t where t.group_id = g.id)          as equipos,
  (select count(*) from public.group_members gm where gm.group_id = g.id) as miembros,
  (select count(*) from public.group_invites gi
     where gi.group_id = g.id and gi.is_active)                          as invitaciones_activas,
  (select count(*) from public.matches m
     join public.teams t2 on t2.id = m.team_id
    where t2.group_id = g.id)                                            as partidos
from public.groups g;

grant select on public.panel_dev_grupos to authenticated;

comment on view public.panel_dev_grupos is
  'Resumen de todos los grupos. Solo devuelve filas a la cuenta de desarrollo.';
