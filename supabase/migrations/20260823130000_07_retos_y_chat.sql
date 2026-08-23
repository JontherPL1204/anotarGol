-- =====================================================================
-- Anotar Gol - 07 | Capitanes, retos entre equipos y chat
-- =====================================================================
-- Ver docs/RETOS_Y_CHAT.md para el porque de cada decision.
--
-- Resumen del modelo de acceso que se establece aqui:
--
--   * Los clubes nuevos nacen PRIVADOS. Ser "descubrible" (aparecer en
--     la busqueda para retarte) no es lo mismo que ser publico.
--   * El chat interno del equipo es SIEMPRE solo de miembros, incluso si
--     el club decide ser publico.
--   * El chat del reto es solo de los dos capitanes, y solo mientras el
--     reto sigue abierto.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Privacidad por defecto
-- ---------------------------------------------------------------------
-- Los clubes existentes conservan lo que tengan; cambia el default.
alter table public.teams alter column is_public set default false;

-- Aparecer en la busqueda de equipos para poder ser retado. No expone
-- plantilla, partidos ni chat: solo el nombre y los colores.
alter table public.teams
  add column if not exists is_discoverable boolean not null default true;

comment on column public.teams.is_discoverable is
  'Aparece en la busqueda para recibir retos. No abre los datos del club.';

drop policy if exists teams_select on public.teams;
create policy teams_select on public.teams
  for select to anon, authenticated
  using (is_public or is_discoverable or public.is_team_member(id));

-- ---------------------------------------------------------------------
-- 2. Capitan
-- ---------------------------------------------------------------------
-- No es un rol nuevo: es una marca sobre la membresia. El capitan suele
-- ser ademas jugador, y necesita conservar ese rol.
alter table public.team_members
  add column if not exists is_captain boolean not null default false;

create unique index if not exists team_members_un_capitan_por_equipo
  on public.team_members (team_id) where is_captain;

-- El owner y el admin tambien pueden ejercer de capitan, para que el
-- equipo no quede bloqueado si el capitan desaparece.
create or replace function public.can_captain(p_team_id uuid)
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
      and (tm.is_captain or tm.role in ('owner', 'admin'))
  );
$$;

grant execute on function public.can_captain(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 3. Terminos del partido
-- ---------------------------------------------------------------------
alter table public.matches
  add column if not exists opponent_team_id      uuid references public.teams (id) on delete set null,
  add column if not exists duration_minutes      smallint not null default 90,
  add column if not exists substitutions_allowed smallint not null default 5;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'matches_duracion_chk') then
    alter table public.matches add constraint matches_duracion_chk
      check (duration_minutes between 10 and 130);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'matches_cambios_chk') then
    alter table public.matches add constraint matches_cambios_chk
      check (substitutions_allowed between 0 and 11);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'matches_no_contra_si_mismo') then
    alter table public.matches add constraint matches_no_contra_si_mismo
      check (opponent_team_id is null or opponent_team_id <> team_id);
  end if;
end
$$;

comment on column public.matches.opponent_team_id is
  'El rival cuando tambien usa la app. Le da acceso de lectura al partido.';

-- El equipo contrario tiene que poder ver el partido acordado.
drop policy if exists matches_select on public.matches;
create policy matches_select on public.matches
  for select to anon, authenticated
  using (
    public.can_view_team(team_id)
    or (opponent_team_id is not null and public.is_team_member(opponent_team_id))
  );

-- ---------------------------------------------------------------------
-- 4. Retos
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_type where typname = 'challenge_status') then
    create type public.challenge_status as enum (
      'pending', 'accepted', 'rejected', 'cancelled', 'expired', 'played');
  end if;
end
$$;

create table if not exists public.challenges (
  id                    uuid primary key default gen_random_uuid(),
  from_team_id          uuid not null references public.teams (id) on delete cascade,
  to_team_id            uuid not null references public.teams (id) on delete cascade,
  status                public.challenge_status not null default 'pending',
  message               text check (char_length(message) <= 500),

  -- Lo que se negocia entre capitanes.
  proposed_kickoff_at   timestamptz not null,
  venue                 text,
  duration_minutes      smallint not null default 90
                          check (duration_minutes between 10 and 130),
  substitutions_allowed smallint not null default 5
                          check (substitutions_allowed between 0 and 11),

  match_id              uuid references public.matches (id) on delete set null,
  created_by            uuid references auth.users (id) on delete set null,
  responded_by          uuid references auth.users (id) on delete set null,
  responded_at          timestamptz,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),

  constraint reto_no_contra_si_mismo check (from_team_id <> to_team_id)
);

-- Un solo reto abierto entre el mismo par de equipos, en cada sentido.
create unique index if not exists challenges_uno_pendiente
  on public.challenges (from_team_id, to_team_id) where status = 'pending';

create index if not exists challenges_to_idx   on public.challenges (to_team_id, status);
create index if not exists challenges_from_idx on public.challenges (from_team_id, status);

-- ---------------------------------------------------------------------
-- 5. Choque de horarios
-- ---------------------------------------------------------------------
-- SECURITY DEFINER porque tiene que mirar la agenda de los dos equipos,
-- incluida la del rival, sin abrirle sus datos a nadie: solo devuelve
-- true o false.
create or replace function public.hay_conflicto_horario(
  p_team_id   uuid,
  p_inicio    timestamptz,
  p_duracion  int default 90,
  p_excluir_challenge uuid default null
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    -- Partidos ya agendados
    select 1
    from public.matches m
    where (m.team_id = p_team_id or m.opponent_team_id = p_team_id)
      and m.status in ('scheduled', 'live')
      and tstzrange(m.kickoff_at,
                    m.kickoff_at + make_interval(mins => m.duration_minutes))
          && tstzrange(p_inicio, p_inicio + make_interval(mins => p_duracion))
  )
  or exists (
    -- Retos ya aceptados que todavia no generaron partido
    select 1
    from public.challenges c
    where (c.from_team_id = p_team_id or c.to_team_id = p_team_id)
      and c.status = 'accepted'
      and (p_excluir_challenge is null or c.id <> p_excluir_challenge)
      and tstzrange(c.proposed_kickoff_at,
                    c.proposed_kickoff_at + make_interval(mins => c.duration_minutes))
          && tstzrange(p_inicio, p_inicio + make_interval(mins => p_duracion))
  );
$$;

grant execute on function public.hay_conflicto_horario(uuid, timestamptz, int, uuid)
  to authenticated;

-- ---------------------------------------------------------------------
-- 6. Chats
-- ---------------------------------------------------------------------
-- Chat interno del club. Nunca se abre al rival, ni siquiera con el
-- club marcado como publico: por eso la politica exige ser miembro y no
-- usa can_view_team.
create table if not exists public.team_messages (
  id         uuid primary key default gen_random_uuid(),
  team_id    uuid not null references public.teams (id) on delete cascade,
  match_id   uuid references public.matches (id) on delete set null,
  user_id    uuid not null references auth.users (id) on delete cascade,
  body       text not null check (char_length(btrim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);

create index if not exists team_messages_idx
  on public.team_messages (team_id, created_at desc);

comment on table public.team_messages is
  'Chat interno del equipo. Solo miembros, siempre, aunque el club sea publico.';

-- Chat temporal entre los dos capitanes, para coordinar el partido.
create table if not exists public.challenge_messages (
  id           uuid primary key default gen_random_uuid(),
  challenge_id uuid not null references public.challenges (id) on delete cascade,
  user_id      uuid not null references auth.users (id) on delete cascade,
  body         text not null check (char_length(btrim(body)) between 1 and 2000),
  created_at   timestamptz not null default now()
);

create index if not exists challenge_messages_idx
  on public.challenge_messages (challenge_id, created_at);

-- Solo los dos capitanes, y solo mientras el reto siga abierto. Cuando
-- se rechaza, se cancela o se juega, el chat se cierra.
create or replace function public.puede_chatear_reto(p_challenge_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.challenges c
    where c.id = p_challenge_id
      and c.status in ('pending', 'accepted')
      and (public.can_captain(c.from_team_id) or public.can_captain(c.to_team_id))
  );
$$;

grant execute on function public.puede_chatear_reto(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 7. RLS
-- ---------------------------------------------------------------------
alter table public.challenges         enable row level security;
alter table public.challenge_messages enable row level security;
alter table public.team_messages      enable row level security;

-- Retos: los ven los dos clubes implicados; solo los capitanes actuan.
drop policy if exists challenges_select on public.challenges;
create policy challenges_select on public.challenges
  for select to authenticated
  using (public.is_team_member(from_team_id) or public.is_team_member(to_team_id));

drop policy if exists challenges_insert on public.challenges;
create policy challenges_insert on public.challenges
  for insert to authenticated
  with check (public.can_captain(from_team_id));

drop policy if exists challenges_update on public.challenges;
create policy challenges_update on public.challenges
  for update to authenticated
  using (public.can_captain(from_team_id) or public.can_captain(to_team_id))
  with check (public.can_captain(from_team_id) or public.can_captain(to_team_id));

drop policy if exists challenges_delete on public.challenges;
create policy challenges_delete on public.challenges
  for delete to authenticated
  using (public.can_captain(from_team_id));

-- Chat del reto: los dos capitanes, mientras este abierto.
drop policy if exists challenge_messages_select on public.challenge_messages;
create policy challenge_messages_select on public.challenge_messages
  for select to authenticated
  using (public.puede_chatear_reto(challenge_id));

drop policy if exists challenge_messages_insert on public.challenge_messages;
create policy challenge_messages_insert on public.challenge_messages
  for insert to authenticated
  with check (user_id = auth.uid() and public.puede_chatear_reto(challenge_id));

drop policy if exists challenge_messages_delete on public.challenge_messages;
create policy challenge_messages_delete on public.challenge_messages
  for delete to authenticated
  using (user_id = auth.uid());

-- Chat interno: miembros del club. Nada de can_view_team aqui.
drop policy if exists team_messages_select on public.team_messages;
create policy team_messages_select on public.team_messages
  for select to authenticated
  using (public.is_team_member(team_id));

drop policy if exists team_messages_insert on public.team_messages;
create policy team_messages_insert on public.team_messages
  for insert to authenticated
  with check (user_id = auth.uid() and public.is_team_member(team_id));

drop policy if exists team_messages_delete on public.team_messages;
create policy team_messages_delete on public.team_messages
  for delete to authenticated
  using (user_id = auth.uid() or public.can_admin_team(team_id));

-- ---------------------------------------------------------------------
-- 8. RPC del flujo de reto
-- ---------------------------------------------------------------------

-- Retar a otro equipo.
create or replace function public.retar_equipo(
  p_from_team_id uuid,
  p_to_team_id   uuid,
  p_kickoff      timestamptz,
  p_venue        text default null,
  p_duracion     int  default 90,
  p_cambios      int  default 5,
  p_mensaje      text default null
)
returns public.challenges
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_reto public.challenges;
begin
  if not public.can_captain(p_from_team_id) then
    raise exception 'Solo el capitán puede retar a otro equipo'
      using errcode = '42501';
  end if;

  if p_from_team_id = p_to_team_id then
    raise exception 'Un equipo no puede retarse a sí mismo' using errcode = '23514';
  end if;

  if p_kickoff <= now() then
    raise exception 'La fecha del partido tiene que ser futura' using errcode = '23514';
  end if;

  if public.hay_conflicto_horario(p_from_team_id, p_kickoff, p_duracion) then
    raise exception 'Ya tienes un partido a esa hora' using errcode = '23505';
  end if;

  insert into public.challenges (
    from_team_id, to_team_id, proposed_kickoff_at, venue,
    duration_minutes, substitutions_allowed, message, created_by
  )
  values (
    p_from_team_id, p_to_team_id, p_kickoff, p_venue,
    p_duracion, p_cambios, p_mensaje, auth.uid()
  )
  returning * into v_reto;

  return v_reto;
end;
$$;

-- Ajustar los terminos mientras se negocia. Cualquiera de los dos
-- capitanes, solo con el reto pendiente.
create or replace function public.actualizar_terminos_reto(
  p_challenge_id uuid,
  p_kickoff      timestamptz default null,
  p_venue        text        default null,
  p_duracion     int         default null,
  p_cambios      int         default null
)
returns public.challenges
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_reto public.challenges;
begin
  select * into v_reto from public.challenges where id = p_challenge_id;

  if v_reto.id is null then
    raise exception 'El reto no existe' using errcode = 'P0002';
  end if;

  if v_reto.status <> 'pending' then
    raise exception 'Este reto ya no está en negociación' using errcode = '23514';
  end if;

  if not (public.can_captain(v_reto.from_team_id)
          or public.can_captain(v_reto.to_team_id)) then
    raise exception 'Solo los capitanes pueden cambiar los términos'
      using errcode = '42501';
  end if;

  update public.challenges
  set proposed_kickoff_at   = coalesce(p_kickoff, proposed_kickoff_at),
      venue                 = coalesce(p_venue, venue),
      duration_minutes      = coalesce(p_duracion, duration_minutes),
      substitutions_allowed = coalesce(p_cambios, substitutions_allowed),
      updated_at            = now()
  where id = p_challenge_id
  returning * into v_reto;

  return v_reto;
end;
$$;

-- Aceptar o rechazar. Aceptar crea el partido con los terminos pactados
-- y lo deja visible para los dos clubes.
create or replace function public.responder_reto(
  p_challenge_id uuid,
  p_aceptar      boolean
)
returns public.challenges
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_reto    public.challenges;
  v_rival   text;
  v_match   uuid;
begin
  select * into v_reto from public.challenges where id = p_challenge_id;

  if v_reto.id is null then
    raise exception 'El reto no existe' using errcode = 'P0002';
  end if;

  if v_reto.status <> 'pending' then
    raise exception 'Este reto ya fue respondido' using errcode = '23514';
  end if;

  -- Responde el equipo retado.
  if not public.can_captain(v_reto.to_team_id) then
    raise exception 'Solo el capitán del equipo retado puede responder'
      using errcode = '42501';
  end if;

  if not p_aceptar then
    update public.challenges
    set status = 'rejected', responded_by = auth.uid(), responded_at = now(),
        updated_at = now()
    where id = p_challenge_id
    returning * into v_reto;
    return v_reto;
  end if;

  -- Al aceptar hay que revisar la agenda de los dos, no solo la propia.
  if public.hay_conflicto_horario(
       v_reto.to_team_id, v_reto.proposed_kickoff_at,
       v_reto.duration_minutes, p_challenge_id) then
    raise exception 'Ya tienes un partido a esa hora' using errcode = '23505';
  end if;

  if public.hay_conflicto_horario(
       v_reto.from_team_id, v_reto.proposed_kickoff_at,
       v_reto.duration_minutes, p_challenge_id) then
    raise exception 'El otro equipo ya tiene un partido a esa hora'
      using errcode = '23505';
  end if;

  select name into v_rival from public.teams where id = v_reto.to_team_id;

  -- El partido lo lleva quien reto (es su marcador); el retado queda
  -- como opponent_team_id y por eso puede verlo.
  insert into public.matches (
    team_id, opponent_team_id, opponent_name, kickoff_at, venue,
    duration_minutes, substitutions_allowed, status, is_home, created_by
  )
  values (
    v_reto.from_team_id, v_reto.to_team_id, v_rival,
    v_reto.proposed_kickoff_at, v_reto.venue,
    v_reto.duration_minutes, v_reto.substitutions_allowed,
    'scheduled', true, auth.uid()
  )
  returning id into v_match;

  update public.challenges
  set status = 'accepted', match_id = v_match, responded_by = auth.uid(),
      responded_at = now(), updated_at = now()
  where id = p_challenge_id
  returning * into v_reto;

  return v_reto;
end;
$$;

create or replace function public.cancelar_reto(p_challenge_id uuid)
returns public.challenges
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_reto public.challenges;
begin
  select * into v_reto from public.challenges where id = p_challenge_id;

  if v_reto.id is null then
    raise exception 'El reto no existe' using errcode = 'P0002';
  end if;

  if not (public.can_captain(v_reto.from_team_id)
          or public.can_captain(v_reto.to_team_id)) then
    raise exception 'Solo los capitanes pueden cancelar' using errcode = '42501';
  end if;

  update public.challenges
  set status = 'cancelled', responded_by = auth.uid(), responded_at = now(),
      updated_at = now()
  where id = p_challenge_id
  returning * into v_reto;

  return v_reto;
end;
$$;

grant execute on function public.retar_equipo(uuid, uuid, timestamptz, text, int, int, text) to authenticated;
grant execute on function public.actualizar_terminos_reto(uuid, timestamptz, text, int, int) to authenticated;
grant execute on function public.responder_reto(uuid, boolean) to authenticated;
grant execute on function public.cancelar_reto(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 9. Vista de retos recibidos, con aviso de choque
-- ---------------------------------------------------------------------
drop view if exists public.retos_recibidos;
create view public.retos_recibidos
with (security_invoker = true)
as
select
  c.id,
  c.from_team_id,
  c.to_team_id,
  t.name        as equipo_retador,
  t.logo_url    as logo_retador,
  c.status,
  c.message,
  c.proposed_kickoff_at,
  c.venue,
  c.duration_minutes,
  c.substitutions_allowed,
  c.match_id,
  c.created_at,
  -- Aviso, no bloqueo: el capitan decide, pero informado.
  public.hay_conflicto_horario(
    c.to_team_id, c.proposed_kickoff_at, c.duration_minutes, c.id) as choca_con_tu_agenda
from public.challenges c
join public.teams t on t.id = c.from_team_id;

grant select on public.retos_recibidos to authenticated;

-- ---------------------------------------------------------------------
-- 10. Tiempo real y updated_at
-- ---------------------------------------------------------------------
-- El chat va por WebSocket, no por sondeo: es lo que lo hace inmediato.
do $$
declare
  t text;
begin
  execute 'drop trigger if exists set_updated_at on public.challenges';
  execute 'create trigger set_updated_at before update on public.challenges
           for each row execute function public.set_updated_at()';

  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['team_messages', 'challenge_messages', 'challenges']
    loop
      if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public' and tablename = t
      ) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    end loop;
  end if;
end
$$;

alter table public.team_messages      replica identity full;
alter table public.challenge_messages replica identity full;
alter table public.challenges         replica identity full;
