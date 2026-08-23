# Anotar Gol

App para ligas de fútbol amateur. Cada liga es un espacio cerrado con sus
equipos; los capitanes se retan entre sí, coordinan el partido y llevan
el marcador en vivo.

Flutter + Supabase (PostgreSQL, Auth, Realtime, Storage).

## Cómo funciona

```
Grupo (liga)          privado; se entra solo con clave de invitación
  └── Equipo          lo funda un capitán con clave de capitán
        └── Jugador   ficha por cédula; la reclama al crear su cuenta
```

**Nadie ve nada sin pertenecer.** El grupo A y el grupo B no saben que el
otro existe. Dentro de una liga, los equipos se ven entre sí para poder
retarse, pero el chat interno de cada club es solo de sus integrantes.

### Las claves

| Clave | La reparte | Qué habilita |
|---|---|---|
| Administrador | el dev, al crear la liga | administrar el grupo y repartir las demás |
| Capitán | el admin de la liga | entrar al grupo **y** fundar un equipo |
| Jugador | el admin de la liga | entrar al grupo, sin fundar nada |
| Equipo | el capitán | sumarse a un club concreto |

Son 8 caracteres en mayúscula, sin `O`/`0` ni `I`/`1`, para poder
dictarlas en voz alta sin que nadie las escriba mal. Quien recibe un
código no necesita saber de qué tipo es: `canjear_clave()` lo averigua.

### La cédula es la identidad

El capitán carga sus 11 jugadores por cédula **antes** de que su gente se
registre. Cuando cada jugador crea su cuenta con esa misma cédula,
recibe su ficha y queda dentro del equipo y de la liga sin pedir nada.

La cédula se valida de verdad (provincia, tipo y dígito verificador), en
la app y en la base. Una vez puesta no se cambia: es lo que une la ficha
con la persona.

Un equipo necesita **11 jugadores con cédula** para poder retar o ser
retado. Si el capitán repite posiciones, se le avisa mientras arma el
equipo, pero no se le bloquea: es su decisión.

### El partido

1. Un capitán reta a otro de su misma liga.
2. Se abre un **chat temporal** entre los dos capitanes.
3. Coordinan horario, lugar, minutos y cambios permitidos.
4. Uno pulsa **"Quedaron de acuerdo"**.
5. El chat se borra, se registra el partido y **recién ahí** aparece en
   el cronograma.

Durante el partido, el marcador va en vivo: registrar un gol lo actualiza
en el celular de todos los que estén mirando.

## Decisiones que conviene conocer antes de tocar el código

**El marcador no se escribe, se calcula.** `matches.team_score` lo
mantiene un trigger a partir de `match_events`. Insertas un gol y sube
solo; lo borras y baja solo. Marcador e historial no pueden
contradecirse. Por eso la app usa el RPC `log_goal()` y nunca un `update`
al marcador.

**El marcador se guarda desde la perspectiva del club**
(`team_score`/`opponent_score` + `is_home`), no como local/visitante, que
es ambiguo cuando juegas de visita. La vista `match_summary` traduce.

**El rol vive en la membresía, no en el usuario.** La misma persona puede
ser capitán de un club y simple hincha de otro.

**Un jugador puede estar en varias ligas, nunca en dos equipos de la
misma.** Se enfrentarían y no se sabría de qué lado juega.

**La `anon key` viaja dentro del APK.** Lo que protege los datos es RLS,
no el secreto de esa clave. Hay 72 políticas y ninguna tabla sin RLS.

## Poner el proyecto a andar

### 1. La base

```bash
# Opción A: pegar supabase/schema_completo.sql en el SQL Editor,
#           y después supabase/seed.sql
# Opción B: con el CLI
npx supabase link --project-ref TU-REF
npx supabase db push
```

Detalles en [`supabase/README.md`](supabase/README.md).

### 2. La app

```bash
cp env/dev.example.json env/dev.json   # y pega URL + clave publicable
flutter pub get
flutter run --dart-define-from-file=env/dev.json
```

Sin ese archivo la app **igual arranca**, en modo local con datos de
ejemplo. Es a propósito: nunca se queda en pantalla negra por falta de
backend.

### 3. La cuenta de desarrollo

No se otorga desde la app. Se inserta a mano:

```sql
insert into public.app_admins (user_id, note)
values ('<uuid del usuario>', 'cuenta de desarrollo');
```

El dev no pertenece a ningún equipo ni grupo, no figura en ningún
listado ni contador, y no deja rastro en las columnas que otros pueden
leer. Puede verlo y modificarlo todo, incluido borrar ligas enteras. Lo
único que no puede es escribir en los chats: un mensaje suyo aparecería
firmado por alguien que nadie conoce.

## Estructura

```
lib/
  core/          arranque de Supabase, sesión, validación de cédula
  models/        modelos con fromMap/toMap
  repositories/  todo el acceso a datos
  data/          fuente de datos (local o remota) y gestión del club
  screens/       pantallas
  widgets/       componentes reutilizables
supabase/
  migrations/    29 migraciones, en orden
  seed.sql       club de ejemplo
  schema_completo.sql  las migraciones concatenadas (generado)
docs/            plan, auditoría, diseño de retos y chat, evidencia académica
test/            54 pruebas
```

Regla del proyecto: **los widgets no hablan con Supabase**. Pasan por los
repositorios. Así la interfaz no depende del backend y las pruebas no
tocan la red.

## Verificar

```bash
flutter analyze     # sin issues
flutter test        # 54 pruebas
```

## Estado

Lo que funciona en la app: inicio con marcador en vivo, plantilla
editable, equipos rivales con plantilla generada, ranking de goleadores e
historial, registro con cédula, login y cuenta.

Lo que está en la base pero todavía no tiene pantalla: grupos e
invitaciones, retos entre capitanes, los dos chats, cronograma y tabla de
posiciones.

Antes de publicar en las tiendas hay pendientes que no son de código:
política de privacidad, formulario de datos, y —por tener chat— la
obligación de poder reportar y bloquear. Está detallado en
[`docs/AUDITORIA_DEL_PLAN.md`](docs/AUDITORIA_DEL_PLAN.md).
