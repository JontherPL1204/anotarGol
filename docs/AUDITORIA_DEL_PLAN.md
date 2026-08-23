# Auditoría del plan de continuidad

Revisión de `PLAN_CONTINUIDAD_ANOTAR_GOL.md` contra el código real, con
foco en lo que faltaba para poder lanzar. Fecha: 21 de agosto de 2026.

## Veredicto

El plan es un buen diagnóstico. Lee bien el producto, identifica las
debilidades reales (datos quemados, sin persistencia, test roto,
`applicationId` de ejemplo) y ordena las fases con criterio.

Donde se queda corto es en **ejecutabilidad**: describe *qué* hacer pero
deja sin decidir casi todo lo que hay que decidir, y no llega al nivel
de detalle donde aparecen los bloqueadores de lanzamiento. Las secciones
5 y 8 son en su mayoría listas de "definir X", "confirmar Y". Un plan que
termina con "la siguiente decisión debería ser…" no se puede ejecutar.

Además tiene un problema de fondo: **recomienda Firebase**, y el
proyecto va con Supabase. Toda la sección 6 quedaba inaplicable.

## Lo que faltaba

Ordenado por gravedad.

### 1. Bloqueador crítico no detectado: la app no tiene internet en release

`android/app/src/main/AndroidManifest.xml` **no declaraba el permiso
`INTERNET`**. Solo estaba en `src/debug/AndroidManifest.xml`, que Flutter
genera para el hot reload.

Consecuencia: la app funciona perfecta en el emulador y en `flutter run`,
y el APK de release **no puede conectarse a ningún backend**. Falla justo
en la entrega, con un error de red genérico y difícil de rastrear.

El plan dedica una sección entera al despliegue Android y no lo menciona.
Es el error más caro de la lista porque solo se descubre después de
compilar release e instalar en un celular.

→ **Corregido** en el manifest principal.

### 2. Sin modelo de seguridad

El plan resume la seguridad de un backend remoto en dos viñetas:
"requiere reglas de seguridad" y "más cuidado con permisos y datos".

Eso no es suficiente. La `anon key` de Supabase **viaja dentro del APK** y
cualquiera puede extraerla con `unzip`. Sin políticas de fila, publicar la
app equivale a publicar la base de datos con permiso de escritura: un
tercero podría borrar la plantilla entera con un `curl`.

→ **Corregido**: `…_04_rls.sql` define el modelo completo (anónimo →
viewer → coach → admin → owner) sobre las 9 tablas.

### 3. El rol estaba en el usuario, no en la membresía

El modelo propuesto ponía `role` y `teamId` dentro de `users`. Eso obliga
a que cada persona pertenezca a un solo equipo y tenga un solo rol.

Rompe en el primer caso real: alguien que entrena un equipo y sigue a
otro como hincha. Migrar eso después implica reescribir todas las reglas
de seguridad.

→ **Corregido**: tabla `team_members (team_id, user_id, role)`.

### 4. `homeScore` / `awayScore` es ambiguo

El plan propone guardar el marcador como local/visitante. Cuando el
equipo juega de visitante, ¿cuál de los dos números es el nuestro? Toda
consulta de estadísticas necesitaría un `case` sobre otra columna que el
modelo no tenía.

→ **Corregido**: `team_score` / `opponent_score` + `is_home`. La vista
`match_summary` traduce a local/visitante para la UI.

### 5. La decisión más importante quedó sin tomar

Sección 6, paso 8: *"Calcular marcador desde eventos o guardarlo
sincronizado"*. Es exactamente la decisión que define si el marcador y el
historial pueden contradecirse.

→ **Decidido**: se guarda en `matches`, pero lo escribe un trigger a
partir de `match_events`. Insertas un gol y el marcador sube solo; lo
borras y baja solo. Una sola fuente de verdad, sin lógica duplicada en
Dart.

### 6. Faltaban dos tablas necesarias

- **`match_lineups`** (convocatoria por partido). Sin ella no existe el
  concepto de "partidos jugados", y la fase 4 pide estadísticas por
  jugador. Goles sin partidos jugados no es una estadística.
- **`seasons`**. Sin temporada, los goles de 2026 y los de 2027 se suman
  en el mismo total para siempre.

→ **Agregadas**.

### 7. Ninguna restricción de integridad

El modelo era una lista de campos. No impedía asignar un gol a un jugador
de otro club, dos jugadores con el mismo dorsal, un minuto 300, ni un
autogol que fuera una tarjeta amarilla.

En una base compartida entre varios dispositivos, esos datos entran por
un bug de la app y ya no salen.

→ **Corregido**: llaves foráneas compuestas `(player_id, team_id)`,
índices únicos parciales por dorsal activo y `check` sobre minuto,
autogol y asistencia.

### 8. Sin gestión de credenciales ni entornos

El plan no dice dónde viven la URL y la clave del backend, ni cómo se
separa desarrollo de producción. Es el camino corto a que la clave
termine hardcodeada en `main.dart` y en el repositorio.

→ **Corregido**: `--dart-define-from-file`, `env/dev.example.json`, y
`env/*.json` ignorado por git.

### 9. Realtime no estaba en el plan

El banner de la app ya dice *"Seguimiento en vivo del partido"*, y la
sección 4 lista "marcador en vivo" como visión de producto. Pero ninguna
fase lo implementa: la fase 5 solo habla de "sincronizar datos".

→ **Corregido**: `matches`, `match_events` y `players` publicados en
Realtime, con `replica identity full` y streams en los repositorios.

### 10. Sin migraciones ni entorno reproducible

"Crear una base de datos" no es un entregable si no queda escrito cómo
recrearla. Sin migraciones versionadas, el esquema vive solo en el panel
web y nadie puede levantar una copia.

→ **Corregido**: 6 migraciones ordenadas + `seed.sql` + un
`schema_completo.sql` para pegar de una sola vez.

### 11. Faltaba decidir la lectura pública

El plan pregunta "¿habrá login?" pero no resuelve el caso más obvio de
esta app: el hincha que solo quiere ver el marcador y no se va a
registrar.

→ **Decidido**: `teams.is_public`. Con eso, un usuario anónimo lee
plantilla, calendario y marcador; escribir sigue requiriendo rol.

### 12. Lo legal aparece como viñeta suelta

"Agregar política de privacidad si usa datos personales" está en una
lista de siete puntos, al mismo nivel que "preparar capturas". Si hay
login por correo, la política de privacidad y el formulario de
**Seguridad de los datos** son requisitos de Google Play: sin ellos la
ficha no se publica.

→ **Pendiente**, es tarea tuya. Pero ya está señalado como bloqueador,
no como detalle.

## Lo que el plan sí acertó

Vale decirlo:

- Detectó que el test buscaba `Icons.add` y la UI usa `Icons.sports_soccer`.
- Detectó el `applicationId` `com.example…` y la firma de debug.
- La separación modelos / repositorios / pantallas es la correcta.
- "No introducir estado avanzado hasta que haya una necesidad real" es
  buen criterio y se respetó: no se agregó Provider ni Riverpod.

## Lo que se hizo

**Base de datos** (`supabase/`)

- 9 tablas, 5 enums, 2 vistas, 17 funciones, 6 triggers y 34 políticas RLS
  (cifras contadas contra la base ya desplegada, no estimadas).
- Marcador derivado por trigger desde los eventos.
- Realtime en partidos, eventos y plantilla.
- Buckets `team-logos` y `player-photos` con permisos por equipo.
- `seed.sql` con los 11 titulares de `plantilla.dart` y el partido del
  domingo que hoy es texto fijo en `homescreen.dart`.

**App** (`lib/`)

- `core/` — arranque de Supabase y configuración por entorno.
- `models/` — 8 modelos con `fromMap`/`toMap`.
- `repositories/` — 6 repositorios. Los widgets no hablan con Supabase.
- `main.dart` — inicializa el backend sin romper si no hay credenciales.

**Lanzamiento**

- Permiso `INTERNET` en el manifest principal.
- `applicationId` y `namespace` → `com.anotargol.app`, con `MainActivity`
  movido al paquete nuevo.
- Nombre visible: "Anotar Gol". Manifest web y `<title>` corregidos.
- Firma de release por `key.properties` (con fallback a debug).

**Pruebas**

- `widget_test.dart` reescrito: 4 pruebas de marcador, calendario y
  navegación.
- `models_test.dart` nuevo: 11 pruebas de reglas de negocio (autogol,
  local/visitante, valores desconocidos).

## Qué falta y no es opcional

Honestidad sobre el estado real:

1. ~~Nada de esto se ejecutó.~~ **La base sí: aplicada y verificada el
   22/08/2026** contra el proyecto real (PostgreSQL 17.6). Ver "Tercera
   entrega". Lo que sigue sin ejecutarse es el **código Dart**: en este
   equipo no hay Flutter, así que nada de `lib/` se ha compilado.

2. **`flutter pub get` es obligatorio** antes de nada. Hasta que se
   descargue `supabase_flutter`, los archivos nuevos no compilan. Es la
   única verificación que falta y solo la puedes correr tú.

3. ~~La UI sigue sin usar la base.~~ **Hecho el 22/08/2026.**
   `plantilla.dart` y `homescreen.dart` ahora piden los datos a
   `ClubDataSource`, y el marcador registra goles reales cuando hay un
   partido en vivo. Ver "Segunda entrega" más abajo.

4. **No hay pantallas de login ni de administración.** `AuthRepository`
   existe; la UI de registro, no. Hoy el club se administra desde el
   panel de Supabase. Es el siguiente bloque grande.

5. **Offline sigue sin resolver.** Es el único punto donde Firebase era
   mejor: Firestore trae caché offline incorporada y Supabase no. Si el
   equipo juega en canchas sin señal, hace falta una caché local
   (`sqflite` o `drift`) sincronizando contra Postgres. Es trabajo real,
   no una dependencia que se agrega.

6. **Íconos.** Siguen siendo los de Flutter por defecto.

7. **Política de privacidad y formulario de Seguridad de los datos** de
   Google Play, si se publica con login por correo.

## Segunda entrega (22/08/2026): las pantallas usan la base

El puente entre la capa de datos y la interfaz. La pieza central es
`lib/data/club_data_source.dart`: una interfaz con dos implementaciones.

- `LocalClubDataSource` — datos de ejemplo, sin red.
- `SupabaseClubDataSource` — la base real, vía los repositorios.

Las pantallas reciben una y no saben cuál es. Eso resuelve tres cosas a
la vez: la app sigue arrancando sin backend (demo, clase, sin internet),
las pruebas no tocan red, y conectar Supabase no obligó a reescribir la
interfaz.

**Lo que cambió**

- `plantilla.dart` — deja de tener los 11 jugadores dentro del widget.
  Carga desde la fuente, con estados de carga, error (con reintentar),
  vacío y *pull to refresh*. Color por línea del campo.
- `homescreen.dart` — ya no guarda datos. El marcador salió a
  `widgets/marcador_card.dart` y el próximo partido a
  `widgets/proximo_partido_card.dart`, para que el archivo no vuelva a
  crecer sin control (era una debilidad señalada en el plan).
- **El marcador tiene dos modos y elige solo.** Si hay un partido `live`
  en la base, el número sale de `matches.team_score`, cantar un gol
  inserta un evento y el cambio llega a los demás dispositivos por
  Realtime. Si no hay backend o no hay partido en curso, funciona como el
  contador en memoria de siempre.
- **Reiniciar el marcador ahora pide confirmación** en modo en vivo:
  borra goles del historial, no es un `_goles = 0`.
- `data/demo_club.dart` — los datos de ejemplo en un solo lugar, con los
  mismos UUID que `seed.sql`.
- `widgets/estado_vacio.dart` — los "estados vacíos" que pedía la fase 2.

**Pruebas**: 9 de widgets (5 en modo local, 4 en modo en vivo con una
fuente falsa, incluida la actualización por tiempo real y el diálogo de
confirmación) más las 11 de modelos.

**Lo que sigue sin estar verificado**: nada de esto se compiló. Ver el
punto 1 de la lista de arriba.

## Tercera entrega (22/08/2026): la base está viva

Ya no es SQL en un archivo. Aplicado contra el proyecto real, en orden,
sin un solo error:

- Las 6 migraciones + `seed.sql`.
- **El trigger funciona**: el partido de ejemplo quedó en 2-1 con
  resultado `W` sin que nadie escribiera el marcador; sale solo de los
  4 eventos.
- La vista `player_stats` devuelve lo correcto: Gabriel Mina y Ronny
  Benítez con 1 gol, Diego López con 1 asistencia, Sebastián Méndez con
  1 amarilla.
- RLS activa en 9 de 9 tablas, 34 políticas, 2 buckets, Realtime en
  `matches`, `match_events` y `players`.

**Prueba de seguridad**: se atacó la base desde fuera con la clave
publicable, que es exactamente lo que puede hacer cualquiera que
descomprima el APK. Ocho intentos:

| Intento | Resultado |
|---|---|
| Leer plantilla, marcador y goleadores | Permitido (es un club público) |
| Borrar la plantilla entera | 0 filas afectadas |
| Insertar un jugador falso | 401, viola la política RLS |
| Falsear el marcador a 99 | 0 filas afectadas |
| Meter un gol por RPC | 401, viola la política RLS |
| Leer los miembros del club | Devuelve vacío |

Y después del ataque se contó la base directamente: siguen los 11
jugadores, 0 intrusos, el marcador en 2 y los 4 eventos. Nada se movió.

**Repositorio**: <https://github.com/JontherPL1204/anotarGol> — 170
archivos. Se verificó que no subiera ningún archivo de credenciales ni
la URL del proyecto, la clave publicable o la contraseña dentro del
contenido. `env/dev.json` se queda local, ignorado por `.gitignore:48`.

## Orden sugerido

1. Crear el proyecto en Supabase y aplicar `schema_completo.sql` +
   `seed.sql`. Verificar que el partido de ejemplo salga 2-1 calculado
   por el trigger.
2. `flutter pub get`, luego `flutter analyze` y `flutter test`.
3. ~~Conectar `plantilla.dart` y el marcador de `homescreen.dart`.~~
   Hecho el 22/08/2026.
4. **Verificar la segunda entrega**: `flutter pub get`, `flutter test`,
   y luego poner un partido en `live` desde el SQL editor para comprobar
   que el marcador de la app lo toma y que el gol viaja entre dos
   dispositivos.
5. Pantallas de login y de gestión de plantilla (CRUD de jugadores y
   partidos). Hoy eso se hace desde el panel de Supabase.
6. Íconos, política de privacidad, keystore y primer APK.
