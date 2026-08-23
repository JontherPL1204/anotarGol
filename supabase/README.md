# Base de datos — Anotar Gol

Base Postgres en Supabase para la app. Incluye esquema, seguridad por
fila (RLS), marcador en vivo y los datos que hoy están quemados en el
código.

## Qué hay aquí

| Archivo | Para qué |
|---|---|
| `migrations/…_00_extensions_enums.sql` | Tipos del dominio (`match_status`, `team_role`, …) |
| `migrations/…_01_core_schema.sql` | Tablas, llaves, índices y restricciones |
| `migrations/…_02_functions_triggers.sql` | Marcador derivado, perfiles, permisos y RPC |
| `migrations/…_03_views.sql` | `player_stats` y `match_summary` |
| `migrations/…_04_rls.sql` | **Quién puede leer y escribir cada cosa** |
| `migrations/…_05_realtime_storage.sql` | Marcador en vivo y buckets de imágenes |
| `seed.sql` | Los 11 titulares y el próximo partido |
| `schema_completo.sql` | Las 6 migraciones concatenadas (archivo generado) |

## Cómo aplicarla

### Opción A — Panel de Supabase (la más rápida)

1. Crea el proyecto en <https://supabase.com/dashboard>. Guarda la
   contraseña de la base: no se puede volver a ver.
2. Entra a **SQL Editor → New query**.
3. Pega el contenido de `schema_completo.sql` y ejecútalo.
4. Nueva query, pega `seed.sql` y ejecútalo. Debe devolver una fila con
   `Deportivo Andino | finished | 2 | 1 | W`. Si ves ese 2-1 calculado
   solo, el trigger del marcador funciona.
5. **Project Settings → API**: copia la `Project URL` y la `anon public`.

### Opción B — CLI (si vas a versionar cambios)

```bash
cd anotarGol
npx supabase login
npx supabase link --project-ref TU-REF   # la ref está en la URL del panel
npx supabase db push                     # aplica migrations/ en orden
```

Para desarrollo local con Docker: `npx supabase start` levanta una copia
completa y aplica migraciones y seed automáticamente.

## Conectar la app

```bash
cd anotarGol
cp env/dev.example.json env/dev.json     # y pega URL + anon key
flutter pub get
flutter run --dart-define-from-file=env/dev.json
```

Sin ese archivo la app **igual arranca**, en modo local con los datos de
ejemplo. Eso es a propósito: nunca se queda en pantalla negra por falta
de backend.

## Tomar el control del club

`seed.sql` crea el equipo sin dueño, para que la app funcione en modo
lectura desde el primer minuto. Después de registrarte en la app:

```sql
select public.claim_team('a0000000-0000-4000-8000-000000000001');
```

Quedas como `owner` y ya puedes editar plantilla y partidos.

## Modelo de datos

```
teams ──┬── team_members ── auth.users ── profiles
        ├── seasons
        ├── players ─────────┐
        ├── team_settings    │
        └── matches ──┬── match_events (goles, tarjetas, cambios)
                      └── match_lineups (once inicial)
```

Tres decisiones que conviene entender antes de tocar nada:

**1. El marcador no se escribe, se calcula.**
`matches.team_score` y `opponent_score` los mantiene un trigger a partir
de `match_events`. Si insertas un gol, el marcador sube solo; si borras
el gol, baja solo. Nunca pueden contradecirse con el historial. Por eso
la app usa el RPC `log_goal()` en vez de un `update` al marcador.

**2. El marcador se guarda desde la perspectiva del club.**
No `home_score`/`away_score` (ambiguo cuando juegas de visitante), sino
`team_score`/`opponent_score` + `is_home`. La vista `match_summary` ya
traduce eso a local/visitante y añade el resultado `W`/`D`/`L`.

**3. El rol vive en la membresía, no en el usuario.**
La misma persona puede ser entrenador de un club y simple hincha de
otro. Por eso `team_members(team_id, user_id, role)`.

## Seguridad

La `anon key` viaja dentro del APK: cualquiera puede extraerla. **Lo que
protege los datos es RLS**, no el secreto de esa clave.

| Quién | Puede |
|---|---|
| Anónimo | Leer equipos con `is_public = true` |
| `viewer` / `player` | Leer todo su equipo, aunque sea privado |
| `coach` | Además: jugadores, partidos y eventos |
| `admin` | Además: miembros y ajustes |
| `owner` | Además: borrar el equipo |

La `service_role` key se salta RLS por completo. **Nunca** la pongas en
la app Flutter ni en el repositorio.

### Verificar que RLS está puesta

```sql
-- Debe devolver 9 filas, todas con rowsecurity = true
select tablename, rowsecurity
from pg_tables
where schemaname = 'public'
order by tablename;
```

## Marcador en vivo

`matches`, `match_events` y `players` están publicados en Realtime. Para
probarlo: pon un partido en vivo y registra un gol desde el SQL Editor
mientras la app está abierta.

```sql
update public.matches
set status = 'live'
where id = 'd0000000-0000-4000-8000-000000000002';

select public.log_goal('d0000000-0000-4000-8000-000000000002'::uuid);
```

## Antes de publicar

- [ ] **Auth → Providers**: decide si dejas registro abierto por email.
- [ ] **Auth → URL Configuration**: agrega la redirect URL si usas
      recuperación de contraseña o enlaces mágicos.
- [ ] **Database → Backups**: el plan gratuito no hace backup diario.
- [ ] Revisa el **Security Advisor** del panel; debería salir limpio.
- [ ] Si la app recoge correos, necesitas política de privacidad para
      Google Play.
