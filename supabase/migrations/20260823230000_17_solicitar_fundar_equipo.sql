-- =====================================================================
-- Anotar Gol - 17 | Pedirle permiso a la administración para fundar
-- =====================================================================
-- Complemento de la clave de capitán: quien entró con clave de jugador
-- y sí quiere armar su equipo no queda en un callejón sin salida. Pide
-- permiso desde la app y el administrador del grupo aprueba o rechaza.
--
-- Aprobar es exactamente lo mismo que entregarle una clave de capitán:
-- enciende `group_members.puede_fundar_equipo`.
-- =====================================================================

do $$
begin
  if not exists (select 1 from pg_type where typname = 'estado_solicitud') then
    create type public.estado_solicitud as enum ('pendiente', 'aprobada', 'rechazada');
  end if;
end
$$;

create table if not exists public.solicitudes_equipo (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references public.groups (id) on delete cascade,
  user_id      uuid not null references auth.users (id) on delete cascade,
  mensaje      text check (char_length(mensaje) <= 300),
  nombre_equipo text check (char_length(btrim(nombre_equipo)) <= 80),
  estado       public.estado_solicitud not null default 'pendiente',
  resuelta_por uuid references auth.users (id) on delete set null,
  resuelta_at  timestamptz,
  created_at   timestamptz not null default now()
);

-- Una solicitud pendiente por persona y grupo: no se spamea al admin.
create unique index if not exists solicitudes_una_pendiente
  on public.solicitudes_equipo (group_id, user_id) where estado = 'pendiente';

create index if not exists solicitudes_grupo_idx
  on public.solicitudes_equipo (group_id, estado);

alter table public.solicitudes_equipo enable row level security;

-- Ves las tuyas; el admin ve las de su grupo.
drop policy if exists solicitudes_select on public.solicitudes_equipo;
create policy solicitudes_select on public.solicitudes_equipo
  for select to authenticated
  using (user_id = auth.uid() or public.es_admin_del_grupo(group_id));

drop policy if exists solicitudes_insert on public.solicitudes_equipo;
create policy solicitudes_insert on public.solicitudes_equipo
  for insert to authenticated
  with check (user_id = auth.uid() and public.es_miembro_del_grupo(group_id));

drop policy if exists solicitudes_update on public.solicitudes_equipo;
create policy solicitudes_update on public.solicitudes_equipo
  for update to authenticated
  using (public.es_admin_del_grupo(group_id))
  with check (public.es_admin_del_grupo(group_id));

-- Retirar la propia solicitud.
drop policy if exists solicitudes_delete on public.solicitudes_equipo;
create policy solicitudes_delete on public.solicitudes_equipo
  for delete to authenticated
  using (user_id = auth.uid() and estado = 'pendiente');

create or replace function public.solicitar_fundar_equipo(
  p_group_id      uuid,
  p_nombre_equipo text default null,
  p_mensaje       text default null
)
returns public.solicitudes_equipo
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_s public.solicitudes_equipo;
begin
  if not public.es_miembro_del_grupo(p_group_id) then
    raise exception 'No perteneces a ese grupo' using errcode = '42501';
  end if;

  if public.puedo_crear_equipo(p_group_id) then
    raise exception 'Ya puedes fundar tu equipo, no hace falta pedir permiso'
      using errcode = '23514';
  end if;

  insert into public.solicitudes_equipo (group_id, user_id, nombre_equipo, mensaje)
  values (p_group_id, auth.uid(), nullif(btrim(coalesce(p_nombre_equipo,'')),''), p_mensaje)
  on conflict (group_id, user_id) where estado = 'pendiente'
    do update set mensaje = excluded.mensaje,
                  nombre_equipo = excluded.nombre_equipo
  returning * into v_s;

  return v_s;
end;
$$;

create or replace function public.responder_solicitud(
  p_solicitud_id uuid,
  p_aprobar      boolean
)
returns public.solicitudes_equipo
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_s public.solicitudes_equipo;
begin
  select * into v_s from public.solicitudes_equipo where id = p_solicitud_id;

  if v_s.id is null then
    raise exception 'Esa solicitud no existe' using errcode = 'P0002';
  end if;

  if not public.es_admin_del_grupo(v_s.group_id) then
    raise exception 'Solo un administrador del grupo puede responder'
      using errcode = '42501';
  end if;

  if v_s.estado <> 'pendiente' then
    raise exception 'Esa solicitud ya fue respondida' using errcode = '23514';
  end if;

  if p_aprobar then
    -- Aprobar es entregarle la llave de capitán.
    update public.group_members
    set puede_fundar_equipo = true
    where group_id = v_s.group_id and user_id = v_s.user_id;
  end if;

  update public.solicitudes_equipo
  set estado = case when p_aprobar then 'aprobada' else 'rechazada' end,
      resuelta_por = auth.uid(),
      resuelta_at = now()
  where id = p_solicitud_id
  returning * into v_s;

  return v_s;
end;
$$;

grant execute on function public.solicitar_fundar_equipo(uuid, text, text) to authenticated;
grant execute on function public.responder_solicitud(uuid, boolean)         to authenticated;

-- La bandeja del administrador, con quién pide y qué pide.
drop view if exists public.solicitudes_del_grupo;
create view public.solicitudes_del_grupo
with (security_invoker = true)
as
select
  s.id, s.group_id, s.user_id, s.nombre_equipo, s.mensaje, s.estado,
  s.created_at, s.resuelta_at,
  p.display_name as solicitante,
  p.email        as correo
from public.solicitudes_equipo s
left join public.profiles p on p.id = s.user_id;

grant select on public.solicitudes_del_grupo to authenticated;
