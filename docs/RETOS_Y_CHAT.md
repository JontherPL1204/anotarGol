# Retos entre equipos, coordinación y chat

Especificación del subsistema pedido el 23/08/2026. Se escribe antes de
construirlo porque toca el modelo de permisos, y equivocarse ahí es caro.

## Qué se pidió

1. La información es **por equipo**: quien es de otro equipo no ve la
   información del club ni su chat interno.
2. **Chat interno del equipo**, habilitado durante el partido.
3. El **capitán** edita el horario de su próximo partido.
4. Un capitán puede **retar** al capitán de otro equipo.
5. Si hay match, se concreta el partido y se coordinan **horario, lugar,
   minutos jugados y cambios permitidos**. Solo de capitán a capitán.
6. Al acordarse, el partido aparece en el **cronograma**.
7. Lista de **equipos que te retan**, sin que los horarios choquen.
8. **Reservas** (los cambios).
9. Al hacer match se abre un **chat temporal** entre los dos capitanes.
10. El chat debe sentirse **inmediato**.

## Una decisión que hay que tomar primero

El sistema de rivales que ya existe y el de retos **no son lo mismo**, y
conviene que convivan:

| | `rivals` (ya construido) | Retos entre `teams` (nuevo) |
|---|---|---|
| Qué es | Libreta privada de contrarios | Otro club real, con sus usuarios |
| Quién lo crea | Tu club, para sí mismo | Existe por su cuenta |
| Plantilla | La cargas tú, o se inventa | La administra el otro club |
| Sirve para | Equipos que no usan la app | Equipos que sí la usan |

Los dos caminos terminan en un `match`. La plantilla imaginaria es
justamente la salida para el primer caso.

## Modelo de datos

### Capitán

Un capitán por equipo. No es un rol nuevo: es una marca sobre la
membresía, porque el capitán además tiene un rol (suele ser jugador).

```
team_members.is_captain boolean not null default false
índice único parcial: un solo capitán por equipo
```

`can_captain(team_id)` = eres el capitán, o `owner`/`admin` del club
(para que un equipo no quede bloqueado si el capitán desaparece).

### Retos

```
challenges
  id
  from_team_id, to_team_id        -- quién reta a quién
  status                          -- pending | accepted | rejected
                                  -- | cancelled | expired | played
  message                         -- el texto del reto
  -- Lo que se negocia:
  proposed_kickoff_at
  venue
  duration_minutes                -- "minutos jugados"
  substitutions_allowed           -- "cambios permitidos"
  -- Trazabilidad:
  created_by, responded_by, responded_at, expires_at
  match_id                        -- se llena al concretarse
```

Reglas:

- Un equipo no se reta a sí mismo.
- No dos retos `pending` entre los mismos dos equipos.
- Al aceptar, se crea el `match` y se copian los términos acordados.

### Choque de horarios

`hay_conflicto_horario(team_id, inicio, duracion)` devuelve true si el
equipo ya tiene un partido o un reto aceptado que se solapa. Se usa para
dos cosas: avisar antes de proponer, y filtrar la lista de retos
recibidos que no encajan en la agenda.

### Chats

Dos, con reglas distintas:

```
team_messages       -- chat interno del club
  team_id, user_id, body, created_at
  Solo miembros del equipo. Nunca visible para el rival,
  ni siquiera si el club es público.

challenge_messages  -- chat temporal capitán a capitán
  challenge_id, user_id, body, created_at
  Solo los dos capitanes implicados.
  Se abre al proponerse el reto y se cierra cuando el reto
  termina (rechazado, cancelado o partido jugado).
```

### Reservas

Ya existe `match_lineups.is_starter`: `false` es el banco. Falta
`substitutions_allowed` en el partido y validar que no se excedan.

## Inmediatez del chat

Se pidió que el chat responda al instante. Se resuelve con **Supabase
Realtime**, no con sondeo:

- Los mensajes viajan por WebSocket. La latencia típica es de décimas de
  segundo, no de segundos.
- Nada de "revisar cada N segundos": eso gasta batería y siempre llega
  tarde.
- El mensaje se pinta en pantalla **antes** de que el servidor confirme
  (envío optimista) y se marca como enviado cuando vuelve. Si falla, se
  muestra en rojo con opción de reintentar. Así se siente inmediato
  aunque la red tarde.
- `team_messages` y `challenge_messages` van publicadas en Realtime con
  `replica identity full`, igual que `matches` y `match_events`.

## Privacidad

Regla que cambia respecto de lo que hay hoy:

- Los clubes nuevos nacen **privados**. `is_public` pasa a ser una
  decisión explícita, no el valor por defecto.
- `is_public = true` abre **solo** plantilla, calendario y marcador —
  lo que un hincha querría ver.
- Los chats, los retos y los miembros son **siempre** de miembros. Ni
  con el club público se abren.

## Grupos (añadido el 23/08/2026)

Encima de todo lo anterior hay una capa más: los **grupos** (ligas,
torneos, barrios). Es la frontera de privacidad principal.

```
groups
  └── teams
        └── team_members
```

- El grupo A y el grupo B **no saben nada** el uno del otro.
- Entrar a un grupo exige una **clave de invitación**. Al iniciar sesión
  por primera vez, una cuenta sin grupo no ve absolutamente nada: lo
  primero que se le pide es el código.
- Un reto **nunca cruza grupos**: solo puedes retar dentro del tuyo.
- Una persona puede estar en varios grupos con equipos distintos. En el
  perfil aparece un **selector de grupo** (`mis_grupos()`).

### Choques de horario de un jugador

- Dentro de **un mismo grupo**: nunca pueden encimarse. Es un error.
- Entre **grupos distintos**: se permite, y es problema del jugador
  resolverlo. La app lo muestra como aviso, no como bloqueo.

`conflictos_del_jugador()` devuelve los solapamientos con una bandera
`mismo_grupo` que distingue error de aviso.

### Códigos de invitación

Ocho caracteres, mayúsculas, sin `O`/`0` ni `I`/`1` para que se puedan
dictar en voz alta sin confusión. Admiten límite de usos y vencimiento.

## Cierre del chat: "Quedaron de acuerdo"

Flujo final acordado:

1. El capitán reta. Se abre el chat temporal entre los dos capitanes.
2. Coordinan ahí: horario, lugar, minutos y cambios permitidos.
3. Uno pulsa **"Quedaron de acuerdo"**.
4. Aviso: *este chat temporal se borrará, ¿deseas continuar?*
5. Si confirma: **se borra el chat**, se registra el partido y **recién
   entonces** aparece en el cronograma.

El borrado no es cosmético: el chat de coordinación no tiene por qué
ocupar espacio para siempre. Lo hace un trigger sobre `challenges`, no
cada RPC, para que ningún camino nuevo se olvide de limpiar.

## Orden de construcción

1. Migración 07: capitán, retos, chats, conflicto de horarios, RLS.
2. Verificar contra la base real, incluido un intento de leer el chat
   ajeno con la clave pública.
3. App: repositorios y modelos.
4. Pantallas: retos recibidos/enviados, coordinación, los dos chats,
   cronograma.
5. Pruebas.
