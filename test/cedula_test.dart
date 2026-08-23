// Validación de cédula ecuatoriana.
//
// El mismo algoritmo vive en Dart y en Postgres (`es_cedula_valida`).
// Estos casos son exactamente los que se corrieron contra la base real,
// así que si alguna de las dos implementaciones se desvía, esta prueba
// lo delata.
//
// Resultado obtenido en Postgres:
//   1750959676 -> true    (la cédula de referencia)
//   1234567890 -> false   (dígito verificador incorrecto)
//   1750959675 -> false   (verificador cambiado)
//   0102030405 -> false
//   9950959676 -> false   (provincia 99 no existe)
//   175095967  -> false   (9 dígitos)
//   17509596761-> false   (11 dígitos)
//   1760959676 -> false

import 'package:flutter_test/flutter_test.dart';

import 'package:diego_javier_lopez_zambrano/core/cedula.dart';

/// Genera una cédula válida a partir de nueve dígitos, con el mismo
/// algoritmo. Sirve para no depender de cédulas reales de nadie.
String cedulaValidaDesde(String nueve) {
  var suma = 0;
  for (var i = 0; i < 9; i++) {
    var v = int.parse(nueve[i]) * (i.isEven ? 2 : 1);
    if (v > 9) v -= 9;
    suma += v;
  }
  return nueve + ((10 - (suma % 10)) % 10).toString();
}

void main() {
  group('Cedula.esValida', () {
    test('acepta la cédula de referencia', () {
      expect(Cedula.esValida('1750959676'), isTrue);
    });

    test('rechaza un dígito verificador incorrecto', () {
      // Mismo número, último dígito cambiado.
      expect(Cedula.esValida('1750959675'), isFalse);
      expect(Cedula.esValida('1750959670'), isFalse);
    });

    test('rechaza los mismos casos que rechazó Postgres', () {
      for (final invalida in [
        '1234567890',
        '1750959675',
        '0102030405',
        '9950959676',
        '175095967',
        '17509596761',
        '1760959676',
      ]) {
        expect(Cedula.esValida(invalida), isFalse, reason: invalida);
      }
    });

    test('rechaza provincias que no existen', () {
      // 00, 25 a 29 y 31 en adelante no son provincias. 30 sí (exterior).
      expect(Cedula.esValida(cedulaValidaDesde('001234567')), isFalse);
      expect(Cedula.esValida(cedulaValidaDesde('251234567')), isFalse);
      expect(Cedula.esValida(cedulaValidaDesde('991234567')), isFalse);
      expect(Cedula.esValida(cedulaValidaDesde('301234567')), isTrue,
          reason: '30 es válida: inscritos en el exterior');
    });

    test('rechaza el tercer dígito de 6 en adelante', () {
      // Solo persona natural.
      expect(Cedula.esValida(cedulaValidaDesde('176123456')), isFalse);
      expect(Cedula.esValida(cedulaValidaDesde('179123456')), isFalse);
      expect(Cedula.esValida(cedulaValidaDesde('175123456')), isTrue);
    });

    test('rechaza lo que no sean 10 dígitos', () {
      expect(Cedula.esValida(''), isFalse);
      expect(Cedula.esValida(null), isFalse);
      expect(Cedula.esValida('175095967'), isFalse);
      expect(Cedula.esValida('17509596761'), isFalse);
      expect(Cedula.esValida('175095967a'), isFalse);
      expect(Cedula.esValida('175 959676'), isFalse);
    });

    test('ignora espacios alrededor', () {
      expect(Cedula.esValida('  1750959676  '), isTrue);
    });

    test('acepta cualquier cédula generada con el algoritmo', () {
      for (var i = 0; i < 40; i++) {
        final c = cedulaValidaDesde('175095${i.toString().padLeft(3, '0')}');
        expect(Cedula.esValida(c), isTrue, reason: c);
      }
    });
  });

  group('Cedula.error', () {
    test('dice qué está mal, no solo que está mal', () {
      expect(Cedula.error(''), 'Escribe tu cédula');
      expect(Cedula.error('abc'), 'La cédula son solo números');
      expect(Cedula.error('17509'), 'Faltan dígitos: son 10');
      expect(Cedula.error('17509596761'), 'Sobran dígitos: son 10');
      expect(Cedula.error('9950959676'),
          'Los dos primeros dígitos no son una provincia válida');
      expect(Cedula.error('1760959676'),
          'El tercer dígito no corresponde a una persona');
      expect(Cedula.error('1750959675'), 'Esa cédula no existe: revisa los dígitos');
    });

    test('devuelve null cuando la cédula es correcta', () {
      expect(Cedula.error('1750959676'), isNull);
    });
  });

  group('Cedula.formatear', () {
    test('separa el dígito verificador', () {
      expect(Cedula.formatear('1750959676'), '175095967-6');
    });

    test('deja pasar lo que no tenga 10 dígitos', () {
      expect(Cedula.formatear('123'), '123');
    });
  });
}
