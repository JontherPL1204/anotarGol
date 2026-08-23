/// Validación de la cédula ecuatoriana.
///
/// Espeja exactamente `public.es_cedula_valida()` de la migración 20.
/// Está en los dos lados a propósito:
///
///   * En la app, para decirle al usuario que se equivocó **mientras
///     escribe**, sin esperar un viaje al servidor.
///   * En la base, porque una validación que solo vive en el cliente no
///     es una validación: cualquiera puede escribir directo a la API.
///
/// Si se cambia una, hay que cambiar la otra. La prueba de
/// `test/cedula_test.dart` usa los mismos casos que se corrieron contra
/// Postgres, así que una divergencia se nota.
class Cedula {
  const Cedula._();

  /// `true` si la cédula es válida: 10 dígitos, provincia real, persona
  /// natural y dígito verificador correcto.
  ///
  /// No basta con contar diez dígitos: eso deja pasar `1234567890`, y
  /// entonces la cédula no identifica a nadie.
  static bool esValida(String? cedula) {
    final c = (cedula ?? '').trim();

    if (c.length != 10 || !RegExp(r'^[0-9]{10}$').hasMatch(c)) return false;

    // Provincia: 01 a 24, o 30 para quienes se inscriben en el exterior.
    final provincia = int.parse(c.substring(0, 2));
    if ((provincia < 1 || provincia > 24) && provincia != 30) return false;

    // Tercer dígito menor que 6 = persona natural.
    if (int.parse(c[2]) >= 6) return false;

    // Coeficientes 2,1,2,1,2,1,2,1,2 sobre los nueve primeros; si el
    // producto pasa de 9 se le restan 9.
    var suma = 0;
    for (var i = 0; i < 9; i++) {
      var valor = int.parse(c[i]) * (i.isEven ? 2 : 1);
      if (valor > 9) valor -= 9;
      suma += valor;
    }

    final verificador = (10 - (suma % 10)) % 10;
    return verificador == int.parse(c[9]);
  }

  /// El motivo del rechazo, para poder decírselo al usuario en vez de un
  /// "cédula inválida" a secas.
  static String? error(String? cedula) {
    final c = (cedula ?? '').trim();

    if (c.isEmpty) return 'Escribe tu cédula';
    if (!RegExp(r'^[0-9]+$').hasMatch(c)) return 'La cédula son solo números';
    if (c.length < 10) return 'Faltan dígitos: son 10';
    if (c.length > 10) return 'Sobran dígitos: son 10';

    final provincia = int.parse(c.substring(0, 2));
    if ((provincia < 1 || provincia > 24) && provincia != 30) {
      return 'Los dos primeros dígitos no son una provincia válida';
    }

    if (int.parse(c[2]) >= 6) return 'El tercer dígito no corresponde a una persona';

    if (!esValida(c)) return 'Esa cédula no existe: revisa los dígitos';

    return null;
  }

  /// Formatea para mostrar: `175095967-6`.
  static String formatear(String cedula) {
    final c = cedula.trim();
    if (c.length != 10) return c;
    return '${c.substring(0, 9)}-${c[9]}';
  }
}
