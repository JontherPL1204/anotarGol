# Plan de continuidad para Anotar Gol

> **Nota de revisión (21/08/2026).** Este documento se auditó y se
> ejecutó parcialmente. Dos cosas cambiaron:
>
> 1. **La base de datos es Supabase, no Firebase.** Las recomendaciones de
>    Firebase de las secciones 6 y 12 quedan sin efecto. La base ya está
>    escrita en `supabase/` — ver su `README.md`.
> 2. **Se encontró un bloqueador de lanzamiento que este plan no vio:**
>    el permiso `INTERNET` solo existía en el manifest de debug, así que
>    ningún APK de release podía conectarse a un backend. Ya está corregido.
>
> El detalle de lo que le faltaba a este plan, lo que se implementó y lo
> que sigue pendiente está en [`AUDITORIA_DEL_PLAN.md`](AUDITORIA_DEL_PLAN.md).
> El diagnóstico del estado del proyecto (secciones 2 a 4) sigue siendo
> válido y se conserva tal cual.

Este documento nació fuera del proyecto, para planificar sin tocar el código. Desde el 23/08/2026 vive dentro del repositorio, en `docs/`, junto a lo que describe.

## 1. Resumen ejecutivo

`anotarGol` es una aplicación Flutter con temática de fútbol. Ya tiene una idea visual y funcional clara: una pantalla principal del club, un marcador interactivo, un botón para reiniciar goles, una sección para ver el próximo partido y una pantalla secundaria con la plantilla titular.

El proyecto todavía está en etapa inicial. Se ve bien como prototipo académico o MVP visual, pero para convertirlo en una app más completa necesita ordenar su arquitectura, persistir datos, actualizar pruebas, preparar identidad real de aplicación y definir una estrategia de despliegue.

La recomendación principal es continuar por fases:

1. Validar el entorno Flutter y corregir pruebas.
2. Definir el alcance exacto del producto.
3. Separar datos, modelos, pantallas y lógica.
4. Crear una base de datos para jugadores, partidos, goles y estadísticas.
5. Mejorar la experiencia de usuario.
6. Preparar despliegue Android como primera entrega descargable.
7. Mantener web/PWA como opción rápida para demostraciones.

## 2. Estado actual del proyecto

### Tipo de proyecto

- Framework: Flutter.
- Lenguaje principal: Dart.
- Tipo: aplicación multiplataforma.
- Plataformas presentes en la estructura: Android, iOS, web, Windows, macOS y Linux.
- Nombre técnico del paquete: `diego_javier_lopez_zambrano`.
- Descripción actual en `pubspec.yaml`: `Proyecto Integrador #1`.
- Versión actual: `1.0.0+1`.

Flutter permite construir desde una misma base de código experiencias para móvil, web, escritorio y otros formatos. Eso significa que el proyecto puede terminar como app descargable, pero no está limitado a eso.

### Dependencias actuales

El proyecto usa pocas dependencias:

- `flutter`, como SDK base.
- `cupertino_icons`, dependencia común generada en proyectos Flutter.
- `google_fonts`, usada para mejorar tipografías en la interfaz.
- `flutter_lints`, para reglas de análisis en desarrollo.
- `flutter_test`, para pruebas.

No se detecta todavía una dependencia para:

- Base de datos local.
- Backend remoto.
- Autenticación.
- Manejo de estado avanzado.
- Cliente HTTP.
- Persistencia de preferencias.

### Pantallas existentes

#### `lib/main.dart`

Define la entrada de la app:

- Ejecuta `runApp`.
- Crea `MyApp`.
- Usa `MaterialApp`.
- Desactiva el banner de debug.
- Define título: `Pasión Futbolera`.
- Usa tema Material 3 con colores verde y dorado.
- Carga `Homescreen` como pantalla inicial.

#### `lib/homescreen.dart`

Es la pantalla principal y contiene la mayor parte de la experiencia actual.

Funciones existentes:

- Estado local `_goles`.
- Estado local `_verProximoPartido`.
- Método `_anotarGol` para sumar un gol.
- Método `_reiniciarMarcador` para volver el marcador a 0.
- Método `_toggleInfo` para mostrar u ocultar el próximo partido.
- Navegación hacia `PlantillaScreen` usando `Navigator.push`.

Elementos visuales:

- AppBar verde con título e ícono de trofeo.
- Banner principal de bienvenida.
- Tarjeta de equipo local y acceso a plantilla.
- Marcador del partido.
- Botón para cantar gol.
- Botón de reinicio.
- Botón para ver u ocultar calendario.
- Caja informativa con el próximo encuentro.

#### `lib/plantilla.dart`

Define una pantalla secundaria para mostrar la plantilla titular.

Estado actual:

- Lista fija de 11 jugadores.
- Cada jugador tiene número, nombre y posición.
- La lista está quemada directamente dentro del widget.
- Se usa `ListView.builder` para renderizar los jugadores.

### Documentación actual

El `README.md` funciona más como evidencia académica que como documentación técnica del producto.

Incluye:

- Evidencia de instalación.
- Capturas del entorno.
- Capturas del emulador.
- Capturas de funcionamiento.
- Mención del paquete externo.
- Fragmentos explicando el aumento y reinicio del marcador.

Falta agregar:

- Objetivo del producto.
- Instrucciones limpias para ejecutar.
- Arquitectura.
- Modelo de datos.
- Decisiones técnicas.
- Roadmap.
- Estrategia de despliegue.

## 3. Diagnóstico técnico

### Fortalezas

- La app ya corre conceptualmente como prototipo Flutter.
- La temática está clara: fútbol, club, marcador, plantilla y partido.
- Ya existe navegación entre pantallas.
- Ya se usa un paquete externo (`google_fonts`), lo cual cumple una base de integración.
- La UI inicial tiene identidad visual: verde, dorado, íconos deportivos.
- El uso de `setState` es suficiente para el tamaño actual.
- La estructura multiplataforma ya está generada.

### Debilidades actuales

- Los datos no persisten. Si se cierra la app, los goles se pierden.
- La plantilla está escrita directamente en el widget, no en una fuente de datos.
- El próximo partido también está quemado como texto fijo.
- No hay modelo formal para jugador, equipo, partido o gol.
- No hay base de datos.
- No hay backend.
- No hay autenticación.
- No hay historial de partidos.
- No hay estadísticas acumuladas.
- No hay separación clara entre UI, lógica y datos.
- El test actual parece venir del ejemplo de contador y no coincide con la UI real.
- La configuración Android todavía tiene nombre y `applicationId` de ejemplo.
- La firma de release Android usa configuración debug.
- El manifest web mantiene nombre y descripción genéricos.
- No hay íconos ni branding final.

### Riesgos

- Si se sigue agregando funcionalidad directamente dentro de widgets, el código se volverá difícil de mantener.
- Si se implementa base de datos sin diseñar entidades primero, habrá que rehacer migraciones.
- Si se publica Android con `com.example...`, luego cambiar el identificador puede causar problemas.
- Si se deja la firma debug, no se debe publicar como release real.
- Si la app necesita compartir datos entre dispositivos, una base local no será suficiente.
- Si se quiere usar como marcador en vivo para varias personas, se necesita backend remoto o sincronización.

## 4. Lectura del producto

La idea que ya se ve formada es una app de seguimiento futbolero para un club o equipo. Hoy funciona como pantalla demostrativa, pero se puede convertir en una herramienta real.

### Posible visión del producto

Una app para registrar y consultar información de un equipo de fútbol:

- Plantilla de jugadores.
- Partidos programados.
- Marcador en vivo.
- Goles y eventos del partido.
- Historial de resultados.
- Estadísticas por jugador y por partido.
- Información del club.

### Usuarios posibles

- Hincha o usuario casual que quiere ver marcador y plantilla.
- Entrenador o encargado que registra partidos.
- Jugador que revisa calendario y estadísticas.
- Administrador del club que mantiene la plantilla.

### MVP recomendado

Para una primera versión realista:

- Home con próximo partido y último resultado.
- Lista de jugadores editable.
- Registro de partidos.
- Marcador de partido con goles.
- Historial de partidos.
- Estadísticas básicas.
- Persistencia local o remota según el objetivo.

## 5. Necesidades principales del proyecto

### Producto

- Definir si la app será solo para una entrega académica o para uso real.
- Definir si será de un equipo específico o una app genérica para cualquier equipo.
- Definir si necesita múltiples usuarios.
- Definir si los datos deben compartirse entre celulares.
- Definir si funcionará offline.

### Diseño

- Crear nombre final de app.
- Crear logo e íconos.
- Mejorar pantallas con diseño consistente.
- Evitar que la pantalla principal crezca demasiado en un solo archivo.
- Crear navegación clara: Inicio, Partidos, Plantilla, Estadísticas, Configuración.

### Arquitectura

- Separar modelos de datos.
- Separar repositorios o servicios.
- Separar widgets reutilizables.
- Agregar manejo de estado cuando la app crezca.
- Preparar capa de persistencia.

### Calidad

- Corregir prueba actual.
- Agregar pruebas del marcador.
- Agregar pruebas de navegación.
- Agregar pruebas para base de datos cuando se implemente.
- Ejecutar `flutter analyze` y `flutter test` cuando Flutter esté disponible en el entorno.

### Despliegue

- Corregir nombre visible de la app.
- Corregir `applicationId`.
- Configurar íconos.
- Configurar firma de Android.
- Crear build release.
- Definir si se entrega APK, AAB, web o escritorio.

## 6. Plan para base de datos

La app necesita base de datos si se quiere que los datos no se pierdan y si se busca crecer más allá del contador actual.

### Pregunta clave

Antes de elegir tecnología, hay que decidir:

- ¿Los datos vivirán solo en el celular?
- ¿Los datos deben sincronizarse entre varios usuarios?
- ¿Habrá roles como administrador, entrenador o jugador?
- ¿El marcador debe verse en vivo desde otros dispositivos?
- ¿Se necesita funcionar sin internet?

### Opción A: Base local

Recomendada si:

- La app será usada por una sola persona o un solo dispositivo.
- Se quiere una entrega más rápida.
- No se necesita login.
- No se necesita sincronización.
- La prioridad es aprender persistencia.

Tecnologías posibles:

- SQLite con `sqflite`.
- Drift sobre SQLite para una capa más ordenada y tipada.

Ventajas:

- Funciona offline.
- No requiere servidor.
- Menos configuración inicial.
- Buena para MVP académico.

Desventajas:

- No sincroniza entre celulares por sí sola.
- No hay panel web ni administración remota.
- Compartir datos requiere exportación/importación o backend posterior.

### Opción B: Base remota

Recomendada si:

- Varias personas deben ver la misma información.
- Se quiere login.
- Se quiere marcador en vivo.
- Se quiere administrar partidos y jugadores desde diferentes dispositivos.
- La app apunta a producción real.

Tecnologías posibles:

- Firebase Authentication + Cloud Firestore.
- Supabase Auth + PostgreSQL.
- Backend propio con API y base SQL.

~~Recomendación para este proyecto si se busca crecer de verdad:
Firebase Authentication + Cloud Firestore + Firebase Storage.~~

**Decisión tomada (21/08/2026): Supabase.**

- Supabase Auth para usuarios y roles.
- PostgreSQL para jugadores, partidos, eventos y estadísticas.
- Supabase Storage para fotos de jugadores y escudos.

Razón: los datos de esta app son relacionales (jugador → gol → partido →
temporada) y las estadísticas son agregaciones. En Firestore eso obliga a
desnormalizar y a pagar una lectura por documento, así que una pantalla de
estadísticas cuesta cientos de lecturas; en Postgres es una vista que
devuelve una fila por jugador. Firebase solo gana claro en offline, y ese
punto sigue abierto (ver auditoría).

Ventajas:

- Sincronización entre dispositivos.
- Buen encaje con apps Flutter.
- Permite crecer a roles y tiempo real.
- Evita construir backend desde cero al inicio.

Desventajas:

- Requiere configurar proyecto en la nube.
- Requiere reglas de seguridad.
- Puede generar costos si crece mucho.
- Se necesita más cuidado con permisos y datos.

### Opción C: Híbrida

Recomendada para una versión más madura:

- Base local para funcionar offline.
- Backend remoto para sincronizar cuando haya internet.

No conviene empezar por aquí si el proyecto todavía está en MVP, porque aumenta bastante la complejidad.

### Recomendación de base de datos

Para el siguiente paso inmediato:

- Si es proyecto académico o prototipo: empezar con SQLite/Drift local.
- Si el objetivo es app real para equipo y usuarios: empezar con Firebase desde el diseño de datos.

Mi recomendación práctica:

1. Diseñar primero el modelo de datos.
2. Crear una capa de repositorios aunque la primera versión sea local.
3. Evitar leer y escribir datos directamente desde los widgets.
4. Si se confirma que habrá varios usuarios o datos compartidos, usar Firebase desde la primera versión seria.

### Modelo de datos inicial

#### Tabla/Colección: `teams`

- `id`
- `name`
- `shortName`
- `primaryColor`
- `secondaryColor`
- `logoUrl`
- `createdAt`
- `updatedAt`

#### Tabla/Colección: `players`

- `id`
- `teamId`
- `number`
- `name`
- `position`
- `photoUrl`
- `isActive`
- `createdAt`
- `updatedAt`

#### Tabla/Colección: `matches`

- `id`
- `teamId`
- `opponentName`
- `matchDate`
- `venue`
- `status`: scheduled, live, finished
- `homeScore`
- `awayScore`
- `notes`
- `createdAt`
- `updatedAt`

#### Tabla/Colección: `match_events`

- `id`
- `matchId`
- `playerId`
- `type`: goal, yellowCard, redCard, substitution, note
- `minute`
- `description`
- `createdAt`

#### Tabla/Colección: `users`

- `id`
- `displayName`
- `email`
- `role`: admin, coach, player, viewer
- `teamId`
- `createdAt`

#### Tabla/Colección: `app_settings`

- `id`
- `teamId`
- `theme`
- `defaultScreen`
- `offlineMode`

### Orden recomendado para implementar la base

1. Convertir los jugadores quemados en un modelo `Player`.
2. Crear un repositorio de jugadores.
3. Guardar y leer jugadores desde base local o remota.
4. Crear modelo `Match`.
5. Guardar próximo partido desde base de datos.
6. Crear modelo `MatchEvent`.
7. Registrar goles como eventos, no solo como número.
8. Calcular marcador desde eventos o guardarlo sincronizado.
9. Agregar historial de partidos.
10. Agregar estadísticas por jugador.

## 7. Plan de arquitectura

Cuando se empiece a tocar código, conviene ordenar el proyecto así:

- `lib/main.dart`: arranque de la app.
- `lib/app/`: configuración general, tema y rutas.
- `lib/models/`: modelos como Player, Match, Team, MatchEvent.
- `lib/repositories/`: acceso a datos.
- `lib/services/`: servicios externos, base de datos o autenticación.
- `lib/screens/`: pantallas completas.
- `lib/widgets/`: componentes reutilizables.
- `lib/features/`: alternativa si se prefiere organizar por módulo.

Para el estado:

- Mantener `setState` solo si la app sigue pequeña.
- Usar Provider, Riverpod o Bloc si crecen los módulos.
- No introducir estado avanzado hasta que haya una necesidad real.

## 8. Plan funcional por fases

### Fase 0: Aclarar objetivo

Resultado esperado:

- Saber si será una app académica, demo o producto real.
- Saber si se apunta a Android, web o ambas.
- Saber si se usará base local o remota.

Decisiones pendientes:

- Nombre final.
- Equipo real o ficticio.
- Usuario único o multiusuario.
- Offline o sincronizado.

### Fase 1: Salud técnica

Objetivo:

- Dejar el proyecto verificable.

Tareas:

- Instalar o ubicar Flutter en el PATH del equipo.
- Ejecutar obtención de dependencias.
- Ejecutar análisis estático.
- Ejecutar pruebas.
- Corregir el test actual para que coincida con el botón real del marcador.
- Confirmar que la app corre en emulador o dispositivo físico.

Criterio de salida:

- El proyecto analiza sin errores críticos.
- Las pruebas pasan.
- La app arranca localmente.

### Fase 2: Producto y UI

Objetivo:

- Convertir el prototipo en una experiencia clara.

Tareas:

- Definir nombre final de la app.
- Ajustar textos y branding.
- Crear navegación principal.
- Separar Inicio, Plantilla, Partidos y Estadísticas.
- Mejorar pantalla de plantilla.
- Agregar estados vacíos.
- Preparar UI responsive.

Criterio de salida:

- La app se entiende sin explicación externa.
- Las pantallas principales están separadas.
- El usuario puede navegar de forma natural.

### Fase 3: Base de datos MVP

Objetivo:

- Persistir datos básicos.

Tareas:

- Definir tecnología: local o remota.
- Crear modelos de datos.
- Crear repositorios.
- Migrar plantilla fija a datos persistidos.
- Guardar partidos.
- Guardar eventos de gol.
- Mostrar historial.

Criterio de salida:

- La plantilla no depende de una lista quemada.
- Los partidos se conservan al cerrar la app.
- Los goles quedan registrados en historial.

### Fase 4: Funciones deportivas

Objetivo:

- Hacer que la app tenga valor más allá del marcador.

Tareas:

- CRUD de jugadores.
- CRUD de partidos.
- Registro de goles por jugador.
- Registro de tarjetas.
- Registro de sustituciones.
- Estadísticas básicas.
- Últimos resultados.
- Próximo partido dinámico.

Criterio de salida:

- Se puede manejar una temporada básica desde la app.

### Fase 5: Usuarios y sincronización

Objetivo:

- Preparar uso real por varias personas.

Tareas:

- Agregar autenticación.
- Crear roles.
- Proteger edición de datos.
- Permitir vista pública del marcador.
- Sincronizar datos si se usa backend remoto.

Criterio de salida:

- Un administrador puede editar.
- Otros usuarios pueden consultar.
- Los datos se comparten entre dispositivos.

### Fase 6: Calidad y entrega

Objetivo:

- Preparar una versión presentable.

Tareas:

- Pruebas de widgets.
- Pruebas de repositorios.
- Pruebas de navegación.
- Revisión visual en móvil.
- Revisión de textos.
- Íconos finales.
- Pantalla de carga.
- Manejo de errores.

Criterio de salida:

- La app se puede entregar con confianza.

## 9. Plan de despliegue

### ¿Es una app descargable?

Sí, puede ser descargable. Como es Flutter, el proyecto puede compilarse para Android, iOS, web y escritorio, siempre que el entorno de cada plataforma esté configurado.

Para una primera entrega, la ruta más práctica suele ser Android:

- APK para instalación directa y pruebas internas.
- AAB para publicación formal en Google Play.

También se puede publicar como web/PWA para que se abra desde navegador. Esa opción es muy buena para demos rápidas, pero si el usuario espera "instalar una app en el celular", Android APK/AAB se siente más natural.

### Recomendación de despliegue para este proyecto

#### Entrega inicial recomendada

Android APK interno.

Razones:

- Es más directo para probar en celulares.
- Sirve para validar la idea sin pasar de inmediato por tienda.
- Encaja con el estado actual del proyecto.
- Permite mostrar la app como descargable.

#### Entrega pública posterior

Google Play con Android App Bundle.

Antes de eso se debe:

- Cambiar `applicationId` de `com.example.actividad_integrador_1` a uno propio.
- Cambiar el nombre visible `actividad_integrador_1`.
- Crear íconos definitivos.
- Configurar firma de release.
- Revisar versión.
- Agregar política de privacidad si usa datos personales, login, analíticas o backend.
- Preparar capturas y descripción.

#### Entrega web opcional

Publicar versión web/PWA.

Razones:

- Facilita compartir el proyecto con un enlace.
- Sirve para profesores, clientes o pruebas rápidas.
- No requiere que el usuario instale APK.

Limitación:

- Puede sentirse menos "app descargable" para usuarios no técnicos.

#### iOS

Conviene dejarlo para después, salvo que sea requisito.

Razones:

- Requiere ecosistema Apple.
- Requiere cuenta de desarrollador para publicación.
- Tiene más pasos de firma y revisión.

#### Escritorio

Windows puede ser útil si se quiere una app para una computadora del club, pero no parece la prioridad inicial.

### Ruta recomendada

1. Primero Android APK para validación.
2. Luego web/PWA para compartir fácil.
3. Después Google Play si el proyecto se vuelve público.
4. iOS solo si hay usuarios reales que lo necesiten.

## 10. Checklist antes de tocar código

- Confirmar objetivo de la app.
- Confirmar plataforma principal.
- Confirmar tipo de base de datos.
- Confirmar nombre final.
- Confirmar si habrá login.
- Confirmar si habrá datos reales.
- Confirmar quién edita la información.
- Confirmar si el marcador debe sincronizarse en vivo.

## 11. Primer sprint sugerido

Duración sugerida: 1 semana.

Objetivo:

- Dejar el proyecto limpio, verificable y listo para crecer.

Entregables:

- Entorno Flutter funcionando.
- Pruebas actuales corregidas.
- Decisión de base de datos tomada.
- Modelo de datos aprobado.
- Estructura de carpetas definida.
- Pantallas objetivo dibujadas o listadas.
- Plan de despliegue Android confirmado.

Tareas:

- Revisar instalación de Flutter.
- Correr análisis y pruebas.
- Ajustar test del marcador.
- Definir si la base será local o Firebase.
- Crear diseño de entidades.
- Definir navegación futura.
- Preparar checklist de release Android.

## 12. Decisiones recomendadas

Para avanzar con buen equilibrio entre rapidez y futuro:

- Plataforma principal: Android.
- Entrega inicial: APK interno.
- Entrega secundaria: web/PWA para demo.
- Base de datos: **Supabase (PostgreSQL + Auth + Realtime)**. Ya
  implementada en `supabase/`.
- Arquitectura: modelos + repositorios + pantallas separadas.
- Estado: mantener simple al inicio, subir a Provider/Riverpod cuando haya datos compartidos entre pantallas.
- Prioridad funcional: partidos, jugadores, goles e historial.

## 13. Observaciones de verificación

En este entorno no se pudo ejecutar Flutter porque el comando `flutter` no está disponible en el PATH.

Queda pendiente verificar:

- `flutter --version`
- análisis estático
- pruebas automatizadas
- compilación en Android
- ejecución en emulador o dispositivo físico

También se detectó que el test actual busca un ícono `Icons.add`, pero la UI usa un botón con ícono de balón (`Icons.sports_soccer`). Ese test debe actualizarse cuando se empiece a trabajar en código.

## 14. Fuentes técnicas consultadas

- Flutter: build para móvil, web y escritorio: https://flutter.dev/
- Flutter deployment: https://docs.flutter.dev/deployment
- Flutter Android release: https://docs.flutter.dev/deployment/android
- Flutter web release: https://docs.flutter.dev/deployment/web
- Flutter SQLite cookbook: https://docs.flutter.dev/cookbook/persistence/sqlite
- Firebase para Flutter: https://firebase.google.com/docs/flutter/setup
- Flutter + Firebase: https://docs.flutter.dev/data-and-backend/firebase
- Drift: https://drift.simonbinder.eu/

## 15. Próxima conversación recomendada

La siguiente decisión debería ser:

¿Queremos que Anotar Gol sea una app simple de un solo celular o una app real donde varios usuarios puedan ver y editar partidos?

Esa respuesta define la base de datos, la arquitectura y el tipo de despliegue.
