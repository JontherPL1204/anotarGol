-- =====================================================================
-- Anotar Gol - 38 | La clave otorga el acceso de dev
-- =====================================================================
-- Decisión tomada: la clave no solo abre el panel, CONVIERTE en dev a
-- quien la canjea. Se pidió explícitamente después de plantear el riesgo.
--
-- Lo que eso significa, dicho claro para que quede en el repositorio:
--   quien tenga el código tiene poder total sobre la plataforma. Puede
--   ver y editar todas las ligas, todos los equipos y todos los chats, y
--   borrar ligas enteras. Un código filtrado es una cuenta de dev
--   regalada.
--
-- Por eso se implementa con los resguardos que NO estorban esa decisión:
--   * Se guarda hasheada (bcrypt). Leer la base no revela el código.
--   * Tiene usos contados. Por defecto UNO: sirve para dar de alta a un
--     dev y deja de servir. Una llave maestra permanente sería lo peor
--     de los dos mundos.
--   * Puede vencer y puede revocarse en cualquier momento.
--   * Cada canje queda registrado con quién lo usó y cuándo.
--
-- CORRECCIÓN incluida aquí:
--   El contador de intentos fallidos de la migración 37 no servía. La
--   función registraba el fallo y después lanzaba la excepción, y la
--   excepción aborta la transacción: el registro se deshacía. El bloqueo
--   por fuerza bruta era decorativo.
--   Ahora estas funciones NO lanzan excepción ante una clave incorrecta:
--   devuelven un resultado. Una clave equivocada es un desenlace normal,
--   no una condición excepcional, y así el contador sobrevive.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Claves que dan acceso de dev
-- ---------------------------------------------------------------------
create table if not exists public.dev_claves (
  id         uuid primary key default gen_random_uuid(),
  code_hash  text not null,
  pista      text,                    -- para reconocerla sin revelarla
  max_usos   int not null default 1,
  usos       int not null default 0,
  expires_at timestamptz,
  is_active  boolean not null default true,
  nota       text,
  created_at timestamptz not null default now()
);

comment on table public.dev_claves is
  'Claves que otorgan acceso de desarrollo. Hasheadas, con usos contados y revocables.';

alter table public.dev_claves enable row level security;

-- Solo un dev las ve, y nunca el hash completo: para eso está la vista.
drop policy if exists dev_claves_solo_dev on public.dev_claves;
create policy dev_claves_solo_dev on public.dev_claves
  for all to authenticated
  using (public.es_dev()) with check (public.es_dev());

drop view if exists public.dev_claves_resumen;
create view public.dev_claves_resumen
with (security_invoker = true)
as
select id, pista, max_usos, usos, expires_at, is_active, nota, created_at,
       (is_active
        and (expires_at is null or expires_at > now())
        and usos < max_usos) as vigente
from public.dev_claves;

grant select on public.dev_claves_resumen to authenticated;

-- ---------------------------------------------------------------------
-- 2. Crear una clave de acceso
-- ---------------------------------------------------------------------
-- La primera hay que crearla desde el SQL editor, porque todavía no hay
-- ningún dev para autorizarla:
--
--   select public.crear_clave_dev('TU-CLAVE-LARGA', 1, 7, 'alta inicial');
--
-- Para eso, si no existe ningún dev, la función deja pasar.
create or replace function public.crear_clave_dev(
  p_codigo   text,
  p_max_usos int  default 1,
  p_dias     int  default null,
  p_nota     text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp, extensions
as $$
declare
  v_hay_dev boolean := exists (select 1 from public.app_admins);
  v_id      uuid;
begin
  if v_hay_dev and not public.es_dev() then
    raise exception 'Solo un dev puede crear claves de acceso'
      using errcode = '42501';
  end if;

  if p_codigo is null or char_length(btrim(p_codigo)) < 12 then
    raise exception 'La clave de dev necesita al menos 12 caracteres'
      using errcode = '23514',
            hint = 'Es la llave de toda la plataforma: que sea larga.';
  end if;

  insert into public.dev_claves (code_hash, pista, max_usos, expires_at, nota)
  values (
    extensions.crypt(btrim(p_codigo), extensions.gen_salt('bf', 10)),
    left(btrim(p_codigo), 3) || repeat('*', greatest(0, char_length(btrim(p_codigo)) - 3)),
    greatest(1, coalesce(p_max_usos, 1)),
    case when p_dias is null then null else now() + make_interval(days => p_dias) end,
    p_nota
  )
  returning id into v_id;

  if v_hay_dev then
    perform public.registrar_accion_dev(
      'crear_clave_dev', 'dev_claves', v_id,
      jsonb_build_object('max_usos', p_max_usos, 'nota', p_nota));
  end if;

  return v_id;
end;
$$;

grant execute on function public.crear_clave_dev(text, int, int, text) to authenticated;

create or replace function public.revocar_clave_dev(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.es_dev() then
    raise exception 'Solo un dev' using errcode = '42501';
  end if;

  update public.dev_claves set is_active = false where id = p_id;
  perform public.registrar_accion_dev('revocar_clave_dev', 'dev_claves', p_id, null);
end;
$$;

grant execute on function public.revocar_clave_dev(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 3. Canjear: aquí es donde se otorga el acceso
-- ---------------------------------------------------------------------
-- No lanza excepción ante una clave incorrecta: devuelve el resultado.
-- Si lanzara, la transacción se desharía y el contador de intentos —lo
-- único que frena la fuerza bruta— nunca quedaría guardado.
create or replace function public.canjear_clave_dev(p_codigo text)
returns table (
  ok      boolean,
  motivo  text,
  expira  timestamptz
)
language plpgsql
security definer
set search_path = public, pg_temp, extensions
as $$
declare
  v_uid    uuid := auth.uid();
  v_acceso public.dev_panel_access;
  v_clave  public.dev_claves;
  v_hasta  timestamptz;
begin
  if v_uid is null then
    return query select false, 'Tienes que iniciar sesión.'::text, null::timestamptz;
    return;
  end if;

  select * into v_acceso from public.dev_panel_access where user_id = v_uid;

  if v_acceso.bloqueado_hasta is not null and v_acceso.bloqueado_hasta > now() then
    return query select false,
      format('Demasiados intentos. Vuelve en %s minutos.',
             ceil(extract(epoch from (v_acceso.bloqueado_hasta - now())) / 60))::text,
      null::timestamptz;
    return;
  end if;

  -- Se recorre porque cada clave tiene su propia sal: no se puede buscar
  -- por hash, hay que comprobarlas una a una.
  select * into v_clave
  from public.dev_claves d
  where d.is_active
    and (d.expires_at is null or d.expires_at > now())
    and d.usos < d.max_usos
    and extensions.crypt(btrim(coalesce(p_codigo, '')), d.code_hash) = d.code_hash
  limit 1;

  if v_clave.id is null then
    insert into public.dev_panel_access (user_id, intentos, ultimo_intento)
    values (v_uid, 1, now())
    on conflict (user_id) do update
      set intentos = public.dev_panel_access.intentos + 1,
          ultimo_intento = now(),
          bloqueado_hasta = case
            when public.dev_panel_access.intentos + 1 >= 5
            then now() + interval '15 minutes' else null end;

    -- Este insert SÍ queda: la función no lanza, así que no hay rollback.
    insert into public.dev_audit (user_id, accion, detalle)
    values (v_uid, 'clave_dev_incorrecta',
            jsonb_build_object('intentos', coalesce(v_acceso.intentos, 0) + 1));

    return query select false, 'Clave incorrecta.'::text, null::timestamptz;
    return;
  end if;

  -- Aquí se otorga el acceso.
  insert into public.app_admins (user_id, note)
  values (v_uid, coalesce(v_clave.nota, 'alta por clave de acceso'))
  on conflict (user_id) do nothing;

  update public.dev_claves set usos = usos + 1 where id = v_clave.id;

  v_hasta := now() + interval '30 minutes';

  insert into public.dev_panel_access (user_id, expires_at, intentos, ultimo_intento)
  values (v_uid, v_hasta, 0, now())
  on conflict (user_id) do update
    set expires_at = excluded.expires_at,
        intentos = 0,
        bloqueado_hasta = null,
        ultimo_intento = now();

  insert into public.dev_audit (user_id, accion, tabla, registro_id, detalle)
  values (v_uid, 'acceso_dev_otorgado', 'dev_claves', v_clave.id,
          jsonb_build_object('usos', v_clave.usos + 1, 'de', v_clave.max_usos));

  return query select true, null::text, v_hasta;
end;
$$;

grant execute on function public.canjear_clave_dev(text) to authenticated;

-- ---------------------------------------------------------------------
-- 4. Abrir el panel: mismo arreglo del contador
-- ---------------------------------------------------------------------
drop function if exists public.dev_abrir_panel(text, int);

create or replace function public.dev_abrir_panel(
  p_codigo  text,
  p_minutos int default 30
)
returns table (
  ok     boolean,
  motivo text,
  expira timestamptz
)
language plpgsql
security definer
set search_path = public, pg_temp, extensions
as $$
declare
  v_uid    uuid := auth.uid();
  v_hash   text;
  v_acceso public.dev_panel_access;
  v_hasta  timestamptz;
begin
  if not public.es_dev() then
    return query select false, 'Esta cuenta no tiene panel.'::text, null::timestamptz;
    return;
  end if;

  select * into v_acceso from public.dev_panel_access where user_id = v_uid;

  if v_acceso.bloqueado_hasta is not null and v_acceso.bloqueado_hasta > now() then
    return query select false,
      format('Demasiados intentos. Vuelve en %s minutos.',
             ceil(extract(epoch from (v_acceso.bloqueado_hasta - now())) / 60))::text,
      null::timestamptz;
    return;
  end if;

  select code_hash into v_hash from public.dev_panel_key;

  -- Sin clave de panel definida, basta con ser dev.
  if v_hash is null then
    v_hasta := now() + make_interval(mins => least(greatest(p_minutos, 5), 120));
    insert into public.dev_panel_access (user_id, expires_at, intentos, ultimo_intento)
    values (v_uid, v_hasta, 0, now())
    on conflict (user_id) do update
      set expires_at = excluded.expires_at, intentos = 0,
          bloqueado_hasta = null, ultimo_intento = now();
    return query select true, null::text, v_hasta;
    return;
  end if;

  if extensions.crypt(btrim(coalesce(p_codigo, '')), v_hash) <> v_hash then
    insert into public.dev_panel_access (user_id, intentos, ultimo_intento)
    values (v_uid, 1, now())
    on conflict (user_id) do update
      set intentos = public.dev_panel_access.intentos + 1,
          ultimo_intento = now(),
          bloqueado_hasta = case
            when public.dev_panel_access.intentos + 1 >= 5
            then now() + interval '15 minutes' else null end;

    insert into public.dev_audit (user_id, accion, detalle)
    values (v_uid, 'panel_clave_incorrecta',
            jsonb_build_object('intentos', coalesce(v_acceso.intentos, 0) + 1));

    return query select false, 'Clave incorrecta.'::text, null::timestamptz;
    return;
  end if;

  v_hasta := now() + make_interval(mins => least(greatest(p_minutos, 5), 120));

  insert into public.dev_panel_access (user_id, expires_at, intentos, ultimo_intento)
  values (v_uid, v_hasta, 0, now())
  on conflict (user_id) do update
    set expires_at = excluded.expires_at, intentos = 0,
        bloqueado_hasta = null, ultimo_intento = now();

  insert into public.dev_audit (user_id, accion, detalle)
  values (v_uid, 'panel_abierto', jsonb_build_object('hasta', v_hasta));

  return query select true, null::text, v_hasta;
end;
$$;

grant execute on function public.dev_abrir_panel(text, int) to authenticated;

-- ---------------------------------------------------------------------
-- 5. Renunciar al acceso de dev
-- ---------------------------------------------------------------------
-- Si el acceso se otorga por una clave que puede circular, tiene que
-- haber forma de devolverlo sin pasar por el SQL editor.
create or replace function public.renunciar_a_dev()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.es_dev() then
    return;
  end if;

  insert into public.dev_audit (user_id, accion)
  values (auth.uid(), 'renuncia_a_dev');

  delete from public.dev_panel_access where user_id = auth.uid();
  delete from public.app_admins where user_id = auth.uid();
end;
$$;

grant execute on function public.renunciar_a_dev() to authenticated;

-- Y saber quién tiene acceso, para poder quitárselo a quien no debería.
drop view if exists public.devs_activos;
create view public.devs_activos
with (security_invoker = true)
as
select a.user_id, p.email, p.display_name, a.note, a.created_at,
       (a.user_id = auth.uid()) as soy_yo
from public.app_admins a
left join public.profiles p on p.id = a.user_id
where public.es_dev();

grant select on public.devs_activos to authenticated;

create or replace function public.quitar_dev(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.dev_panel_abierto() then
    raise exception 'Abre el panel antes de quitar accesos' using errcode = '42501';
  end if;

  if p_user_id = auth.uid() then
    raise exception 'Para quitarte el acceso a ti mismo usa renunciar_a_dev()'
      using errcode = '23514';
  end if;

  perform public.registrar_accion_dev('quitar_dev', 'app_admins', p_user_id, null);

  delete from public.dev_panel_access where user_id = p_user_id;
  delete from public.app_admins where user_id = p_user_id;
end;
$$;

grant execute on function public.quitar_dev(uuid) to authenticated;
