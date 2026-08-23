-- =====================================================================
-- Anotar Gol - 02 | Funciones, triggers y RPC
-- =====================================================================
-- Aca vive la logica que la app NO debe reimplementar en Dart:
--   * el marcador se deriva de los eventos (una sola fuente de verdad)
--   * el perfil se crea solo al registrarse
--   * quien crea un equipo queda como owner automaticamente
--   * las funciones de permisos que usara RLS en la migracion 04
-- Todas las funciones fijan search_path para evitar secuestro de esquema.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Utilidades
-- ---------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- Convierte 'Pasion Futbolera FC' -> 'pasion-futbolera-fc' (sin depender
-- de la extension unaccent, que no viene activa por defecto).
create or replace function public.slugify(p_text text)
returns text
language sql
immutable
strict
as $$
  select btrim(
    regexp_replace(
      lower(
        translate(
          p_text,
          'áéíóúàèìòùäëïöüâêîôûñçÁÉÍÓÚÀÈÌÒÙÄËÏÖÜÂÊÎÔÛÑÇ',
          'aeiouaeiouaeiouaeiouncAEIOUAEIOUAEIOUAEIOUNC'
        )
      ),
      '[^a-z0-9]+', '-', 'g'
    ),
    '-'
  );
$$;

-- ---------------------------------------------------------------------
-- Funciones de permisos
-- ---------------------------------------------------------------------
-- IMPORTANTE: son SECURITY DEFINER a proposito. Si una politica RLS de
-- team_members consultara team_members directamente, Postgres entraria en
-- recursion infinita. Al leerla desde una funcion definer, RLS no se
-- vuelve a evaluar y el problema desaparece.

create or replace function public.team_role_of(p_team_id uuid)
returns public.team_role
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select tm.role
  from public.team_members tm
  where tm.team_id = p_team_id
    and tm.user_id = auth.uid();
$$;

create or replace function public.is_team_member(p_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.team_members tm
    where tm.team_id = p_team_id
      and tm.user_id = auth.uid()
  );
$$;

-- Lectura: el equipo es publico, o soy miembro.
create or replace function public.can_view_team(p_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.teams t
    where t.id = p_team_id
      and (t.is_public or public.is_team_member(t.id))
  );
$$;

-- Escritura de datos deportivos: cuerpo tecnico hacia arriba.
create or replace function public.can_edit_team(p_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(public.team_role_of(p_team_id) in ('owner', 'admin', 'coach'), false);
$$;

-- Administracion del club (miembros, ajustes, borrar el equipo).
create or replace function public.can_admin_team(p_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(public.team_role_of(p_team_id) in ('owner', 'admin'), false);
$$;

grant execute on function public.team_role_of(uuid)   to anon, authenticated;
grant execute on function public.is_team_member(uuid) to anon, authenticated;
grant execute on function public.can_view_team(uuid)  to anon, authenticated;
grant execute on function public.can_edit_team(uuid)  to anon, authenticated;
grant execute on function public.can_admin_team(uuid) to anon, authenticated;

-- ---------------------------------------------------------------------
-- Perfil automatico al registrarse
-- ---------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.profiles (id, display_name, email, avatar_url)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data ->> 'display_name',
      new.raw_user_meta_data ->> 'full_name',
      split_part(coalesce(new.email, 'hincha'), '@', 1)
    ),
    new.email,
    new.raw_user_meta_data ->> 'avatar_url'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------
-- Quien crea el equipo queda como owner (y se crean sus ajustes)
-- ---------------------------------------------------------------------
-- Sin esto habria un problema del huevo y la gallina: RLS no te deja
-- crear un equipo del que no eres miembro, ni ser miembro de un equipo
-- que todavia no existe.
create or replace function public.handle_new_team()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.created_by is not null then
    insert into public.team_members (team_id, user_id, role)
    values (new.id, new.created_by, 'owner')
    on conflict (team_id, user_id) do update set role = 'owner';
  end if;

  insert into public.team_settings (team_id)
  values (new.id)
  on conflict (team_id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_team_created on public.teams;
create trigger on_team_created
  after insert on public.teams
  for each row execute function public.handle_new_team();

-- ---------------------------------------------------------------------
-- Un equipo nunca puede quedarse sin owner
-- ---------------------------------------------------------------------
create or replace function public.protect_last_owner()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_team_id uuid := coalesce(old.team_id, new.team_id);
  v_owners  int;
begin
  -- Solo importa si estamos quitando o degradando a un owner.
  if old.role <> 'owner' then
    return coalesce(new, old);
  end if;

  -- Si el equipo entero se esta borrando (cascade), no hay nada que proteger.
  if not exists (select 1 from public.teams where id = v_team_id) then
    return coalesce(new, old);
  end if;

  if tg_op = 'UPDATE' and new.role = 'owner' then
    return new;
  end if;

  select count(*) into v_owners
  from public.team_members
  where team_id = v_team_id and role = 'owner';

  if v_owners <= 1 then
    raise exception 'El equipo debe conservar al menos un owner'
      using errcode = '23514';
  end if;

  return coalesce(new, old);
end;
$$;

drop trigger if exists team_members_protect_last_owner on public.team_members;
create trigger team_members_protect_last_owner
  before update or delete on public.team_members
  for each row execute function public.protect_last_owner();

-- ---------------------------------------------------------------------
-- El marcador se deriva de los eventos
-- ---------------------------------------------------------------------
-- Regla de negocio: un gol en propia puerta suma para el rival. Por eso
-- no basta con contar por 'side'.
create or replace function public.recalc_match_score(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.matches m
  set team_score = coalesce(s.team_score, 0),
      opponent_score = coalesce(s.opponent_score, 0)
  from (
    select
      count(*) filter (
        where e.type = 'goal'
          and ((e.side = 'us' and not e.is_own_goal)
            or (e.side = 'them' and e.is_own_goal))
      )::smallint as team_score,
      count(*) filter (
        where e.type = 'goal'
          and ((e.side = 'them' and not e.is_own_goal)
            or (e.side = 'us' and e.is_own_goal))
      )::smallint as opponent_score
    from public.match_events e
    where e.match_id = p_match_id
  ) s
  where m.id = p_match_id;
end;
$$;

create or replace function public.sync_match_score()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'DELETE' then
    perform public.recalc_match_score(old.match_id);
    return old;
  end if;

  perform public.recalc_match_score(new.match_id);

  -- Si el evento se movio de partido, hay que recalcular tambien el viejo.
  if tg_op = 'UPDATE' and old.match_id is distinct from new.match_id then
    perform public.recalc_match_score(old.match_id);
  end if;

  return new;
end;
$$;

drop trigger if exists match_events_sync_score on public.match_events;
create trigger match_events_sync_score
  after insert or update or delete on public.match_events
  for each row execute function public.sync_match_score();

-- ---------------------------------------------------------------------
-- updated_at automatico
-- ---------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['profiles', 'teams', 'players', 'matches', 'team_settings']
  loop
    execute format('drop trigger if exists set_updated_at on public.%I', t);
    execute format(
      'create trigger set_updated_at before update on public.%I
       for each row execute function public.set_updated_at()', t);
  end loop;
end
$$;

-- =====================================================================
-- RPC que consume la app Flutter
-- =====================================================================

-- Crea equipo + membresia owner + ajustes en una sola transaccion.
create or replace function public.create_team(
  p_name            text,
  p_short_name      text default null,
  p_primary_color   text default '#1B5E20',
  p_secondary_color text default '#FFD700',
  p_is_public       boolean default true
)
returns public.teams
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_team      public.teams;
  v_base_slug text;
  v_slug      text;
  v_suffix    int := 0;
begin
  if auth.uid() is null then
    raise exception 'Debes iniciar sesion para crear un equipo'
      using errcode = '42501';
  end if;

  v_base_slug := nullif(public.slugify(p_name), '');
  v_base_slug := coalesce(v_base_slug, 'equipo');
  v_slug := v_base_slug;

  while exists (select 1 from public.teams t where t.slug = v_slug) loop
    v_suffix := v_suffix + 1;
    v_slug := v_base_slug || '-' || v_suffix;
  end loop;

  insert into public.teams (
    name, short_name, slug, primary_color, secondary_color, is_public, created_by
  )
  values (
    btrim(p_name), nullif(btrim(coalesce(p_short_name, '')), ''), v_slug,
    p_primary_color, p_secondary_color, p_is_public, auth.uid()
  )
  returning * into v_team;

  return v_team;
end;
$$;

-- Adopta un equipo que todavia no tiene owner (sirve para tomar el
-- equipo demo creado por seed.sql tras registrarte por primera vez).
create or replace function public.claim_team(p_team_id uuid)
returns public.team_members
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_member public.team_members;
begin
  if auth.uid() is null then
    raise exception 'Debes iniciar sesion' using errcode = '42501';
  end if;

  if exists (
    select 1 from public.team_members
    where team_id = p_team_id and role = 'owner'
  ) then
    raise exception 'Este equipo ya tiene un owner' using errcode = '42501';
  end if;

  if not exists (select 1 from public.teams where id = p_team_id) then
    raise exception 'El equipo no existe' using errcode = 'P0002';
  end if;

  insert into public.team_members (team_id, user_id, role)
  values (p_team_id, auth.uid(), 'owner')
  on conflict (team_id, user_id) do update set role = 'owner'
  returning * into v_member;

  update public.teams
  set created_by = coalesce(created_by, auth.uid())
  where id = p_team_id;

  return v_member;
end;
$$;

-- Atajo para el boton "!CANTAR GOL!": registra el evento y deja que el
-- trigger actualice el marcador. SECURITY INVOKER a proposito, para que
-- RLS siga decidiendo quien puede anotar.
create or replace function public.log_goal(
  p_match_id  uuid,
  p_player_id uuid              default null,
  p_minute    smallint          default null,
  p_side      public.team_side  default 'us',
  p_assist_player_id uuid       default null,
  p_is_own_goal boolean         default false
)
returns public.match_events
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_team_id uuid;
  v_event   public.match_events;
begin
  select team_id into v_team_id from public.matches where id = p_match_id;

  if v_team_id is null then
    raise exception 'El partido no existe' using errcode = 'P0002';
  end if;

  insert into public.match_events (
    match_id, team_id, player_id, assist_player_id,
    type, side, minute, is_own_goal, created_by
  )
  values (
    p_match_id, v_team_id, p_player_id, p_assist_player_id,
    'goal', p_side, p_minute, p_is_own_goal, auth.uid()
  )
  returning * into v_event;

  return v_event;
end;
$$;

grant execute on function public.create_team(text, text, text, text, boolean) to authenticated;
grant execute on function public.claim_team(uuid) to authenticated;
grant execute on function public.log_goal(uuid, uuid, smallint, public.team_side, uuid, boolean)
  to authenticated;
