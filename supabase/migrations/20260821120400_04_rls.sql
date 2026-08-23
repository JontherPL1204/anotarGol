-- =====================================================================
-- Anotar Gol - 04 | Row Level Security
-- =====================================================================
-- Modelo de acceso:
--
--   anonimo (anon)      -> lee equipos con is_public = true. Nada mas.
--   viewer / player     -> lee todo su equipo (aunque sea privado).
--   coach               -> ademas escribe jugadores, partidos y eventos.
--   admin               -> ademas gestiona miembros y ajustes.
--   owner               -> ademas puede borrar el equipo.
--
-- Sin estas politicas, la anon key publicada dentro del APK permitiria a
-- cualquiera vaciar la base. Esto es el requisito de seguridad que el
-- plan original no cubria.
-- =====================================================================

alter table public.profiles      enable row level security;
alter table public.teams         enable row level security;
alter table public.team_members  enable row level security;
alter table public.seasons       enable row level security;
alter table public.players       enable row level security;
alter table public.matches       enable row level security;
alter table public.match_events  enable row level security;
alter table public.match_lineups enable row level security;
alter table public.team_settings enable row level security;

-- Nota: NO se usa "force row level security". Las funciones SECURITY
-- DEFINER (permisos, recalculo del marcador) pertenecen a postgres y
-- deben poder saltarse RLS para funcionar.

-- ---------------------------------------------------------------------
-- Helper: comparto equipo con este usuario?
-- ---------------------------------------------------------------------
create or replace function public.shares_team_with(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.team_members mine
    join public.team_members theirs on theirs.team_id = mine.team_id
    where mine.user_id = auth.uid()
      and theirs.user_id = p_user_id
  );
$$;

grant execute on function public.shares_team_with(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.shares_team_with(id));

drop policy if exists profiles_insert_self on public.profiles;
create policy profiles_insert_self on public.profiles
  for insert to authenticated
  with check (id = auth.uid());

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- ---------------------------------------------------------------------
-- teams
-- ---------------------------------------------------------------------
drop policy if exists teams_select on public.teams;
create policy teams_select on public.teams
  for select to anon, authenticated
  using (is_public or public.is_team_member(id));

drop policy if exists teams_insert on public.teams;
create policy teams_insert on public.teams
  for insert to authenticated
  with check (created_by = auth.uid());

drop policy if exists teams_update on public.teams;
create policy teams_update on public.teams
  for update to authenticated
  using (public.can_admin_team(id))
  with check (public.can_admin_team(id));

drop policy if exists teams_delete on public.teams;
create policy teams_delete on public.teams
  for delete to authenticated
  using (public.team_role_of(id) = 'owner');

-- ---------------------------------------------------------------------
-- team_members
-- ---------------------------------------------------------------------
drop policy if exists team_members_select on public.team_members;
create policy team_members_select on public.team_members
  for select to authenticated
  using (public.is_team_member(team_id));

drop policy if exists team_members_insert on public.team_members;
create policy team_members_insert on public.team_members
  for insert to authenticated
  with check (public.can_admin_team(team_id));

drop policy if exists team_members_update on public.team_members;
create policy team_members_update on public.team_members
  for update to authenticated
  using (public.can_admin_team(team_id))
  with check (public.can_admin_team(team_id));

-- Un admin puede sacar a alguien; cualquiera puede salirse solo.
drop policy if exists team_members_delete on public.team_members;
create policy team_members_delete on public.team_members
  for delete to authenticated
  using (public.can_admin_team(team_id) or user_id = auth.uid());

-- ---------------------------------------------------------------------
-- Datos deportivos: leen los que pueden ver, escribe el cuerpo tecnico
-- ---------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['seasons', 'players', 'matches', 'match_events', 'match_lineups']
  loop
    execute format('drop policy if exists %I on public.%I', t || '_select', t);
    execute format($fmt$
      create policy %I on public.%I
        for select to anon, authenticated
        using (public.can_view_team(team_id))
    $fmt$, t || '_select', t);

    execute format('drop policy if exists %I on public.%I', t || '_insert', t);
    execute format($fmt$
      create policy %I on public.%I
        for insert to authenticated
        with check (public.can_edit_team(team_id))
    $fmt$, t || '_insert', t);

    execute format('drop policy if exists %I on public.%I', t || '_update', t);
    execute format($fmt$
      create policy %I on public.%I
        for update to authenticated
        using (public.can_edit_team(team_id))
        with check (public.can_edit_team(team_id))
    $fmt$, t || '_update', t);

    execute format('drop policy if exists %I on public.%I', t || '_delete', t);
    execute format($fmt$
      create policy %I on public.%I
        for delete to authenticated
        using (public.can_edit_team(team_id))
    $fmt$, t || '_delete', t);
  end loop;
end
$$;

-- ---------------------------------------------------------------------
-- team_settings
-- ---------------------------------------------------------------------
drop policy if exists team_settings_select on public.team_settings;
create policy team_settings_select on public.team_settings
  for select to anon, authenticated
  using (public.can_view_team(team_id));

drop policy if exists team_settings_insert on public.team_settings;
create policy team_settings_insert on public.team_settings
  for insert to authenticated
  with check (public.can_admin_team(team_id));

drop policy if exists team_settings_update on public.team_settings;
create policy team_settings_update on public.team_settings
  for update to authenticated
  using (public.can_admin_team(team_id))
  with check (public.can_admin_team(team_id));
