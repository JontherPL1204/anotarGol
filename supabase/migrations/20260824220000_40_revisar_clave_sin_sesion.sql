-- =====================================================================
-- Anotar Gol - 40 | Comprobar la clave antes de tener cuenta
-- =====================================================================
-- El registro pasa a pedir la clave de invitacion en el mismo formulario
-- que la cedula y la contrasena. Para poder decirle a la persona QUE
-- hace esa clave mientras la escribe, hay que poder consultarla sin
-- sesion todavia.
--
-- La migracion 36 revoco el permiso de anon sobre todas las funciones, y
-- con razon: 82 estaban abiertas por el permiso que Postgres da a PUBLIC
-- por defecto. Esta es la unica excepcion, y se abre a proposito.
--
-- Que expone: a quien YA TIENE un codigo valido, el nombre de la liga o
-- del equipo al que ese codigo lleva. Nada mas. No lista claves, no
-- devuelve datos del club y no canjea nada: canjear sigue exigiendo
-- sesion.
--
-- Por que es aceptable: el codigo son 8 caracteres de un alfabeto de 32,
-- del orden de 10^12 combinaciones. Adivinarlo no es una via practicable,
-- y quien lo tiene es porque alguien se lo dio.
-- =====================================================================

grant execute on function public.revisar_clave(text) to anon;

comment on function public.revisar_clave is
  'Dice qué hace una clave sin consumirla. Abierta a anon a propósito: el registro la consulta antes de que exista la cuenta.';
