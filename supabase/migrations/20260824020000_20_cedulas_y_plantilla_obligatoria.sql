-- =====================================================================
-- Anotar Gol - 20 | Cédulas: la ficha del jugador y su cuenta
-- =====================================================================
-- Requisito del 24/08/2026:
--
--   * La cuenta se crea con la cédula (10 dígitos).
--   * Al registrarse, la base comprueba si esa cédula ya está cargada
--     como jugador en algún equipo, y le entrega su ficha.
--   * Para fundar un equipo hay que cargar los 11 jugadores obligatorios
--     con su cédula y su posición.
--   * Si el capitán repite posiciones, es cosa suya: se avisa, no se
--     bloquea.
--
-- El orden que esto habilita es el natural de un club: el capitán arma
-- la plantilla por cédula ANTES de que su gente se registre, y cada
-- jugador, al crear su cuenta, aparece ya fichado.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Validación real de la cédula ecuatoriana
-- ---------------------------------------------------------------------
-- No basta con "que tenga 10 dígitos": eso deja pasar cualquier número
-- inventado, y entonces la cédula no sirve para identificar a nadie.
-- Se valida provincia, tipo y dígito verificador (módulo 10).
--
-- Comprobado con 1750959676:
--   coeficientes 2,1,2,1,2,1,2,1,2 -> suma 44 -> (10 - 4) % 10 = 6  OK
create or replace function public.es_cedula_valida(p_cedula text)
returns boolean
language plpgsql
immutable
as $$
declare
  v_c        text := btrim(coalesce(p_cedula, ''));
  v_prov     int;
  v_tercero  int;
  v_suma     int := 0;
  v_digito   int;
  v_valor    int;
  i          int;
begin
  if v_c !~ '^[0-9]{10}$' then
    return false;
  end if;

  -- Provincia: 01 a 24, o 30 para quienes se inscriben en el exterior.
  v_prov := substr(v_c, 1, 2)::int;
  if not (v_prov between 1 and 24) and v_prov <> 30 then
    return false;
  end if;

  -- Tercer dígito menor que 6 = persona natural.
  v_tercero := substr(v_c, 3, 1)::int;
  if v_tercero >= 6 then
    return false;
  end if;

  -- Dígito verificador: coeficientes 2,1,2,1,2,1,2,1,2 sobre los nueve
  -- primeros; si el producto pasa de 9 se le restan 9.
  for i in 1..9 loop
    v_valor := substr(v_c, i, 1)::int * (case when i % 2 = 1 then 2 else 1 end);
    if v_valor > 9 then
      v_valor := v_valor - 9;
    end if;
    v_suma := v_suma + v_valor;
  end loop;

  v_digito := (10 - (v_suma % 10)) % 10;

  return v_digito = substr(v_c, 10, 1)::int;
end;
$$;

comment on function public.es_cedula_valida is
  'Valida cédula ecuatoriana: provincia, tipo y dígito verificador módulo 10.';

grant execute on function public.es_cedula_valida(text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 2. La cédula en la ficha y en la cuenta
-- ---------------------------------------------------------------------
alter table public.players
  add column if not exists cedula  text,
  add column if not exists user_id uuid references auth.users (id) on delete set null;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'players_cedula_chk') then
    alter table public.players add constraint players_cedula_chk
      check (cedula is null or public.es_cedula_valida(cedula));
  end if;
end
$$;

-- Una cédula no puede estar dos veces en el mismo equipo.
create unique index if not exists players_cedula_por_equipo
  on public.players (team_id, cedula) where cedula is not null;

create index if not exists players_cedula_idx  on public.players (cedula);
create index if not exists players_user_idx    on public.players (user_id);

comment on column public.players.cedula is
  'Cédula del jugador. Es lo que une la ficha con la cuenta cuando se registra.';
comment on column public.players.user_id is
  'Cuenta que reclamó esta ficha. Se llena solo al registrarse con la misma cédula.';

alter table public.profiles
  add column if not exists cedula text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'profiles_cedula_chk') then
    alter table public.profiles add constraint profiles_cedula_chk
      check (cedula is null or public.es_cedula_valida(cedula));
  end if;
end
$$;

-- Una cédula, una cuenta.
create unique index if not exists profiles_cedula_uniq
  on public.profiles (cedula) where cedula is not null;

-- ---------------------------------------------------------------------
-- 3. Al registrarse, se le entregan sus fichas
-- ---------------------------------------------------------------------
create or replace function public.vincular_fichas_por_cedula(p_user_id uuid)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_cedula text;
  v_n      int;
begin
  select cedula into v_cedula from public.profiles where id = p_user_id;
  if v_cedula is null then
    return 0;
  end if;

  update public.players
  set user_id = p_user_id
  where cedula = v_cedula and user_id is distinct from p_user_id;

  get diagnostics v_n = row_count;

  -- Estar fichado en un equipo es ser parte del equipo. Si el capitán ya
  -- te cargó, no tienes que pedir permiso para entrar.
  insert into public.team_members (team_id, user_id, role)
  select p.team_id, p_user_id, 'player'
  from public.players p
  where p.cedula = v_cedula
  on conflict (team_id, user_id) do nothing;

  -- Y al equipo se llega por su grupo.
  insert into public.group_members (group_id, user_id, role, puede_fundar_equipo)
  select distinct t.group_id, p_user_id, 'member', false
  from public.players p
  join public.teams t on t.id = p.team_id
  where p.cedula = v_cedula and t.group_id is not null
  on conflict (group_id, user_id) do nothing;

  return v_n;
end;
$$;

grant execute on function public.vincular_fichas_por_cedula(uuid) to authenticated;

-- El perfil ahora guarda la cédula que venga en el registro, y de paso
-- reclama las fichas que le correspondan.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_cedula text := nullif(btrim(coalesce(new.raw_user_meta_data ->> 'cedula', '')), '');
begin
  if v_cedula is not null and not public.es_cedula_valida(v_cedula) then
    v_cedula := null;   -- no se guarda basura; la app ya la valida antes
  end if;

  insert into public.profiles (id, display_name, email, avatar_url, cedula)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data ->> 'display_name',
      new.raw_user_meta_data ->> 'full_name',
      split_part(coalesce(new.email, 'hincha'), '@', 1)
    ),
    new.email,
    new.raw_user_meta_data ->> 'avatar_url',
    v_cedula
  )
  on conflict (id) do nothing;

  if v_cedula is not null then
    perform public.vincular_fichas_por_cedula(new.id);
  end if;

  return new;
end;
$$;

-- Para quien ya tenía cuenta y agrega la cédula después.
create or replace function public.registrar_mi_cedula(p_cedula text)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_c text := btrim(coalesce(p_cedula, ''));
begin
  if auth.uid() is null then
    raise exception 'Debes iniciar sesión' using errcode = '42501';
  end if;

  if not public.es_cedula_valida(v_c) then
    raise exception 'Esa cédula no es válida'
      using errcode = '23514',
            hint = 'Son 10 dígitos y el último es el verificador.';
  end if;

  if exists (select 1 from public.profiles where cedula = v_c and id <> auth.uid()) then
    raise exception 'Esa cédula ya está registrada en otra cuenta'
      using errcode = '23505';
  end if;

  update public.profiles set cedula = v_c where id = auth.uid();

  return public.vincular_fichas_por_cedula(auth.uid());
end;
$$;

grant execute on function public.registrar_mi_cedula(text) to authenticated;

-- ---------------------------------------------------------------------
-- 4. Los 11 obligatorios
-- ---------------------------------------------------------------------
create or replace function public.equipo_habilitado(p_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select (
    select count(*)
    from public.players p
    where p.team_id = p_team_id
      and p.is_active
      and p.cedula is not null
  ) >= 11;
$$;

grant execute on function public.equipo_habilitado(uuid) to authenticated;

comment on function public.equipo_habilitado is
  'Un equipo puede jugar cuando tiene 11 jugadores activos con cédula cargada.';

-- Avisos, no bloqueos. Las posiciones repetidas son decisión del
-- capitán; lo que sí impide jugar es no llegar a 11 con cédula.
create or replace function public.avisos_de_plantilla(p_team_id uuid)
returns table (
  tipo     text,     -- 'bloqueo' | 'aviso'
  mensaje  text
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_total    int;
  v_con_ced  int;
  v_porteros int;
  r          record;
begin
  select count(*) filter (where is_active),
         count(*) filter (where is_active and cedula is not null),
         count(*) filter (where is_active and position = 'GK')
    into v_total, v_con_ced, v_porteros
  from public.players where team_id = p_team_id;

  if v_con_ced < 11 then
    return query select 'bloqueo'::text,
      format('Faltan %s jugadores con cédula para completar los 11 obligatorios.',
             11 - v_con_ced);
  end if;

  if v_total > v_con_ced then
    return query select 'aviso'::text,
      format('%s jugador(es) sin cédula: no cuentan para los 11.',
             v_total - v_con_ced);
  end if;

  if v_porteros = 0 then
    return query select 'aviso'::text, 'No hay ningún portero en la plantilla.';
  elsif v_porteros > 1 then
    return query select 'aviso'::text,
      format('Hay %s porteros. Normalmente juega uno.', v_porteros);
  end if;

  -- Posiciones repetidas: se avisa y se sigue.
  for r in
    select position_detail, count(*) n
    from public.players
    where team_id = p_team_id and is_active and position_detail is not null
    group by position_detail having count(*) > 1
  loop
    return query select 'aviso'::text,
      format('%s jugadores puestos como "%s".', r.n, r.position_detail);
  end loop;

  return;
end;
$$;

grant execute on function public.avisos_de_plantilla(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 5. Sin los 11, no se juega
-- ---------------------------------------------------------------------
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
security definer
set search_path = public, pg_temp
as $$
declare
  v_reto    public.challenges;
  v_grupo_a uuid;
  v_grupo_b uuid;
begin
  if not public.can_captain(p_from_team_id) then
    raise exception 'Solo el capitán puede retar a otro equipo'
      using errcode = '42501';
  end if;

  if p_from_team_id = p_to_team_id then
    raise exception 'Un equipo no puede retarse a sí mismo' using errcode = '23514';
  end if;

  select group_id into v_grupo_a from public.teams where id = p_from_team_id;
  select group_id into v_grupo_b from public.teams where id = p_to_team_id;

  if v_grupo_a is distinct from v_grupo_b then
    raise exception 'Solo puedes retar a equipos de tu mismo grupo'
      using errcode = '42501';
  end if;

  if not public.equipo_habilitado(p_from_team_id) then
    raise exception 'Tu equipo todavía no tiene los 11 jugadores con cédula'
      using errcode = '23514',
            hint = 'Completa la plantilla antes de retar.';
  end if;

  if not public.equipo_habilitado(p_to_team_id) then
    raise exception 'Ese equipo todavía no completó sus 11 jugadores'
      using errcode = '23514';
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

grant execute on function public.retar_equipo(uuid, uuid, timestamptz, text, int, int, text)
  to authenticated;

-- ---------------------------------------------------------------------
-- 6. Estado de la plantilla, para la pantalla del capitán
-- ---------------------------------------------------------------------
drop view if exists public.estado_plantilla;
create view public.estado_plantilla
with (security_invoker = true)
as
select
  t.id                                   as team_id,
  t.name                                 as equipo,
  t.group_id,
  count(p.*) filter (where p.is_active)                          as jugadores,
  count(p.*) filter (where p.is_active and p.cedula is not null) as con_cedula,
  count(p.*) filter (where p.is_active and p.user_id is not null) as ya_registrados,
  greatest(0, 11 - count(p.*) filter (where p.is_active and p.cedula is not null))
                                                                 as faltan,
  public.equipo_habilitado(t.id)                                 as habilitado
from public.teams t
left join public.players p on p.team_id = t.id
group by t.id, t.name, t.group_id;

grant select on public.estado_plantilla to authenticated;

comment on view public.estado_plantilla is
  'Cuánto le falta a cada equipo para poder jugar: 11 jugadores con cédula.';
