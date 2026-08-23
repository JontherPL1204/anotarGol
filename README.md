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

El circuito es **dev → capitán → jugador**. El único que tiene contacto
con el dev son los capitanes.

| Clave | La reparte | Qué habilita |
|---|---|---|
| Liga | el dev, a cada capitán | entrar a la liga **y** fundar un equipo |
| Equipo | el capitán, a su gente | sumarse a ese club |

Un jugador nunca recibe una clave de liga: la de su equipo ya lo mete
también en la liga. Por ahora solo existen dev, capitanes y jugadores.

Son 8 caracteres en mayúscula, sin `O`/`0` ni `I`/`1`, para poder
dictarlas en voz alta sin que nadie las escriba mal. Quien recibe un
código no necesita saber de qué tipo es: `canjear_clave()` lo averigua.

### Nombres

La **liga** nace como "La Liga A", y las siguientes B, C… (después de la
Z sigue AA, AB, como las columnas de una hoja de cálculo). Solo el dev
puede renombrarla; el administrador de la liga puede tocar sus ajustes
pero no su identidad.

El **equipo** lo nombra su capitán y el nombre es obligatorio. El escudo
es opcional.

Cada club lleva además un número dentro de su liga, asignado al crearlo:

| Quién mira | Qué ve |
|---|---|
| El dev | `Equipo 1 (Halcones FC)` |
| Capitanes y jugadores | `Halcones FC` |

El número le da al dev una referencia estable para hablar de un club, y
ordena la liga.

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

### El reloj

A la hora acordada el partido queda **listo para empezar** y el capitán
pulsa iniciar; el reloj cuenta desde ese momento real, no desde la hora
pactada. Maneja descanso, segundo tiempo y minutos agregados.

Un gol registrado sin indicar minuto **lo toma del reloj**: nadie tiene
que calcular en qué minuto va.

No arranca solo al llegar la hora, y es a propósito: los equipos llegan
tarde y la cancha se ocupa. Un partido que se pusiera en marcha solo
contaría minutos que nadie jugó, y los goles quedarían en minutos falsos.

Todo esto va en vivo: registrar un gol lo actualiza en el celular de
todos los que estén mirando.

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
no el secreto de esa clave. Ninguna tabla sin RLS, y sin sesión no se ve
absolutamente nada: no hay acceso anónimo.

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

Se otorga con una **clave de acceso**. La primera se crea desde el SQL
Editor, porque todavía no hay ningún dev que la autorice:

```sql
select public.crear_clave_dev(
  'ESCRIBE-AQUI-UNA-CLAVE-LARGA',  -- mínimo 12 caracteres
  1,                               -- usos: uno y se gasta
  7,                               -- días de validez
  'alta inicial'
);
```

Después, en la app, esa clave convierte tu cuenta en dev.

**Qué significa tener esa clave:** poder total sobre la plataforma —
ver y editar todas las ligas, todos los equipos y todos los chats, y
borrar ligas enteras. Un código filtrado es una cuenta de dev regalada.
Por eso viene con usos contados, vencimiento y se puede revocar
(`revocar_clave_dev`), y cada canje queda registrado con quién lo usó.

Para devolver el acceso: `renunciar_a_dev()`. Para quitárselo a otro:
`quitar_dev(user_id)`, con el panel abierto.

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
  migrations/    39 migraciones, en orden
  seed.sql       liga de prueba con el club de ejemplo dentro
  seed.sql       club de ejemplo
  schema_completo.sql  las migraciones concatenadas (generado)
docs/            plan, auditoría, diseño de retos y chat, evidencia académica
test/            85 pruebas
```

Regla del proyecto: **los widgets no hablan con Supabase**. Pasan por los
repositorios. Así la interfaz no depende del backend y las pruebas no
tocan la red.

## Verificar

```bash
flutter analyze     # sin issues
flutter test        # 85 pruebas
```

## Estado

Lo que funciona en la app: inicio con marcador en vivo, plantilla
editable, equipos rivales con plantilla generada, ranking de goleadores e
historial, registro con cédula, login y cuenta.

Ya hay puerta de entrada: quien inicia sesión sin liga cae en la casilla
de la clave y no puede saltarla. La app le dice **qué hace esa clave
antes de canjearla**, y después lo lleva a fundar su equipo o al equipo
al que acaba de entrar.

Y hay panel de desarrollo: canjear la clave de acceso, ver todas las
ligas con sus equipos, crear ligas, renombrarlas, repartir claves de
capitán y borrar. Se cierra solo a los 30 minutos.

Lo que está en la base pero todavía no tiene pantalla: retos entre
capitanes, los dos chats, cronograma, tabla de posiciones y los
controles del reloj.

Antes de publicar en las tiendas hay pendientes que no son de código:
política de privacidad, formulario de datos, y —por tener chat— la
obligación de poder reportar y bloquear. Está detallado en
[`docs/AUDITORIA_DEL_PLAN.md`](docs/AUDITORIA_DEL_PLAN.md).
