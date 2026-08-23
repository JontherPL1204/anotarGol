-- =====================================================================
-- Anotar Gol - 39 | Numerar también al mover un equipo a una liga
-- =====================================================================
-- Se vio en la base: el club de ejemplo quedó dentro de "Liga de Prueba"
-- pero con `numero_en_grupo` en null, así que el dev lo veía sin número.
--
-- Causa: el trigger de la migración 33 solo corre en INSERT. El club ya
-- existía sin grupo y entró a la liga con un UPDATE (el `on conflict do
-- update` del seed), así que nunca pasó por el numerador.
--
-- Es un caso real, no solo del seed: un equipo puede nacer suelto y
-- entrar a una liga después, o cambiarse de liga.
-- =====================================================================

create or replace function public.asignar_numero_de_equipo()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.group_id is null then
    -- Fuera de una liga el número no significa nada.
    new.numero_en_grupo := null;
    return new;
  end if;

  -- Ya tiene número en la liga en la que está: no se toca. El número es
  -- la referencia estable con la que el dev habla de ese club.
  if new.numero_en_grupo is not null
     and tg_op = 'UPDATE'
     and new.group_id is not distinct from old.group_id then
    return new;
  end if;

  if new.numero_en_grupo is not null and tg_op = 'INSERT' then
    return new;
  end if;

  perform pg_advisory_xact_lock(hashtext(new.group_id::text));

  select coalesce(max(numero_en_grupo), 0) + 1
    into new.numero_en_grupo
  from public.teams
  where group_id = new.group_id
    and id is distinct from new.id;

  return new;
end;
$$;

drop trigger if exists teams_numerar on public.teams;
create trigger teams_numerar
  before insert or update of group_id on public.teams
  for each row execute function public.asignar_numero_de_equipo();

-- Poner número a los que entraron a una liga sin pasar por el trigger.
do $$
declare
  r record;
begin
  for r in
    select id, row_number() over (partition by group_id order by created_at) as n
    from public.teams
    where group_id is not null and numero_en_grupo is null
  loop
    update public.teams set numero_en_grupo = r.n where id = r.id;
  end loop;
end
$$;
