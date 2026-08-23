-- =====================================================================
-- Anotar Gol - 00 | Extensiones y tipos enumerados
-- =====================================================================
-- Se ejecuta primero. Define el vocabulario del dominio como ENUMs de
-- Postgres para que la base rechace valores invalidos (ej. status = "xyz")
-- en lugar de confiar en que el cliente Flutter mande el texto correcto.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- Idempotente: si la migracion se corre dos veces, no falla.
do $$
begin
  -- Rol de una persona DENTRO de un equipo (no es un rol global de la app).
  if not exists (select 1 from pg_type where typname = 'team_role') then
    create type public.team_role as enum ('owner', 'admin', 'coach', 'player', 'viewer');
  end if;

  -- Ciclo de vida de un partido.
  if not exists (select 1 from pg_type where typname = 'match_status') then
    create type public.match_status as enum ('scheduled', 'live', 'finished', 'postponed', 'cancelled');
  end if;

  -- Eventos que ocurren dentro de un partido.
  -- Nota: la asistencia NO es un tipo de evento, es la columna
  -- assist_player_id sobre el evento 'goal' (evita datos duplicados).
  if not exists (select 1 from pg_type where typname = 'match_event_type') then
    create type public.match_event_type as enum (
      'goal',
      'yellow_card',
      'red_card',
      'penalty_missed',
      'substitution_in',
      'substitution_out',
      'note'
    );
  end if;

  -- A que lado pertenece el evento: nuestro equipo o el rival.
  if not exists (select 1 from pg_type where typname = 'team_side') then
    create type public.team_side as enum ('us', 'them');
  end if;

  -- Posicion normalizada. El texto libre ("Lateral Derecho") vive en
  -- players.position_detail para no perder el detalle actual de la app.
  if not exists (select 1 from pg_type where typname = 'player_position') then
    create type public.player_position as enum ('GK', 'DF', 'MF', 'FW');
  end if;
end
$$;
