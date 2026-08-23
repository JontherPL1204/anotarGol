-- =====================================================================
-- Anotar Gol - 05 | Realtime y Storage
-- =====================================================================
-- Realtime es lo que convierte "Seguimiento en vivo del partido" (el
-- texto que ya esta en el banner de la app) en algo real: el hincha ve
-- el gol en su celular en el momento en que el DT lo anota en el suyo.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Publicacion de cambios en vivo
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise notice 'No existe la publicacion supabase_realtime; se omite Realtime.';
    return;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'matches'
  ) then
    alter publication supabase_realtime add table public.matches;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'match_events'
  ) then
    alter publication supabase_realtime add table public.match_events;
  end if;

  -- La plantilla tambien se sincroniza: si el DT da de alta un jugador
  -- desde su celular, aparece en el resto sin recargar.
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'players'
  ) then
    alter publication supabase_realtime add table public.players;
  end if;
end
$$;

-- Necesario para que los eventos UPDATE/DELETE lleguen con la fila
-- completa y Realtime pueda aplicar RLS sobre ellos.
alter table public.matches      replica identity full;
alter table public.match_events replica identity full;
alter table public.players      replica identity full;

-- ---------------------------------------------------------------------
-- Buckets de imagenes
-- ---------------------------------------------------------------------
-- Convencion de ruta: <team_id>/<archivo>. La primera carpeta identifica
-- al equipo y es lo que usan las politicas para decidir quien escribe.
insert into storage.buckets (id, name, public)
values
  ('team-logos',    'team-logos',    true),
  ('player-photos', 'player-photos', true)
on conflict (id) do nothing;

-- Convierte texto a uuid sin reventar si la carpeta no es un uuid.
create or replace function public.safe_uuid(p_text text)
returns uuid
language plpgsql
immutable
as $$
begin
  return p_text::uuid;
exception
  when others then
    return null;
end;
$$;

grant execute on function public.safe_uuid(text) to anon, authenticated;

-- Las politicas sobre storage.objects a veces requieren permisos extra
-- segun el proyecto. Si fallan, la migracion continua y se avisa para
-- crearlas desde el panel (Storage > Policies).
do $$
begin
  drop policy if exists anotar_gol_media_read   on storage.objects;
  drop policy if exists anotar_gol_media_insert on storage.objects;
  drop policy if exists anotar_gol_media_update on storage.objects;
  drop policy if exists anotar_gol_media_delete on storage.objects;

  create policy anotar_gol_media_read on storage.objects
    for select to anon, authenticated
    using (bucket_id in ('team-logos', 'player-photos'));

  create policy anotar_gol_media_insert on storage.objects
    for insert to authenticated
    with check (
      bucket_id in ('team-logos', 'player-photos')
      and public.can_edit_team(public.safe_uuid((storage.foldername(name))[1]))
    );

  create policy anotar_gol_media_update on storage.objects
    for update to authenticated
    using (
      bucket_id in ('team-logos', 'player-photos')
      and public.can_edit_team(public.safe_uuid((storage.foldername(name))[1]))
    );

  create policy anotar_gol_media_delete on storage.objects
    for delete to authenticated
    using (
      bucket_id in ('team-logos', 'player-photos')
      and public.can_edit_team(public.safe_uuid((storage.foldername(name))[1]))
    );
exception
  when insufficient_privilege then
    raise notice 'Sin permisos para crear politicas de storage. Crealas desde el panel de Supabase.';
end
$$;
