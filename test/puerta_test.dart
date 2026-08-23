// Pruebas de la puerta de entrada.
//
// La regla que se verifica es la del modelo de privacidad: sin liga no
// hay nada que mostrar, así que quien inicia sesión y no pertenece a
// ninguna no puede pasar de la casilla de la clave.
//
// Ninguna prueba toca la red: se usa una `Session` falsa.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diego_javier_lopez_zambrano/core/session.dart';
import 'package:diego_javier_lopez_zambrano/models/models.dart';
import 'package:diego_javier_lopez_zambrano/screens/clave_screen.dart';
import 'package:diego_javier_lopez_zambrano/screens/login_screen.dart';
import 'package:diego_javier_lopez_zambrano/screens/puerta.dart';

class _SesionFalsa extends Session {
  _SesionFalsa({
    this.backend = true,
    this.sesion = true,
    MiSituacion? situacionInicial,
    this.claves = const {},
  }) {
    if (situacionInicial != null) situacion = situacionInicial;
  }

  final bool backend;
  final bool sesion;

  /// Código -> qué devuelve `revisar_clave`.
  final Map<String, ClaveRevisada> claves;

  final List<String> canjeadas = [];
  final List<String> revisadas = [];

  @override
  bool get hayBackend => backend;

  @override
  bool get haySesion => sesion;

  @override
  Future<ClaveRevisada> revisarClave(String codigo) async {
    revisadas.add(codigo);
    return claves[codigo.toUpperCase()] ??
        const ClaveRevisada(valida: false, motivo: 'Esa clave no existe.');
  }

  @override
  Future<String?> canjearClave(String codigo) async {
    canjeadas.add(codigo);
    // Una clave de dev no lleva a ninguna liga por sí sola.
    if (Session.pareceClaveDev(codigo)) return null;
    final c = claves[codigo.toUpperCase()];
    if (c == null || !c.valida) return c?.motivo ?? 'Esa clave no existe.';

    situacion = MiSituacion(
      tieneGrupo: true,
      tieneEquipo: c.llevaAEquipo,
      puedeFundar: c.haceCapitan,
      grupo: c.grupo,
      equipo: c.equipo,
    );
    notifyListeners();
    return null;
  }
}

Future<void> _montar(WidgetTester tester, Widget hijo) async {
  tester.view.physicalSize = const Size(1080, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: hijo));
  await tester.pumpAndSettle();
}

const _claveCapitan = ClaveRevisada(
  valida: true,
  tipo: 'capitan',
  descripcion: 'Entras a Liga Norte como capitán y podrás fundar tu equipo.',
  grupo: 'Liga Norte',
);

const _claveEquipo = ClaveRevisada(
  valida: true,
  tipo: 'equipo',
  descripcion: 'Te sumas a Halcones FC como jugador.',
  grupo: 'Liga Norte',
  equipo: 'Halcones FC',
);

const _claveVencida = ClaveRevisada(
  valida: false,
  motivo: 'Esa invitación ya venció.',
);

void main() {
  group('MiSituacion decide la pantalla', () {
    test('sin grupo, lo primero es la clave', () {
      const s = MiSituacion();
      expect(s.necesitaClave, isTrue);
      expect(s.debeFundarEquipo, isFalse);
    });

    test('capitán sin equipo debe fundarlo', () {
      const s = MiSituacion(tieneGrupo: true, puedeFundar: true);
      expect(s.necesitaClave, isFalse);
      expect(s.debeFundarEquipo, isTrue);
      expect(s.esperaQueLoFichen, isFalse);
    });

    test('en la liga, sin equipo y sin poder fundar: espera que lo fichen', () {
      const s = MiSituacion(tieneGrupo: true);
      expect(s.esperaQueLoFichen, isTrue);
    });

    test('con equipo no falta nada', () {
      const s = MiSituacion(tieneGrupo: true, tieneEquipo: true);
      expect(s.necesitaClave, isFalse);
      expect(s.debeFundarEquipo, isFalse);
      expect(s.esperaQueLoFichen, isFalse);
    });
  });

  group('Puerta', () {
    testWidgets('sin backend arranca en modo local, sin pedir clave',
        (tester) async {
      await _montar(tester, Puerta(session: _SesionFalsa(backend: false)));
      expect(find.byType(ClaveScreen), findsNothing);
      expect(find.text('Pasión Futbolera FC'), findsOneWidget);
    });

    testWidgets('con backend y sin sesión, lo primero es el login',
        (tester) async {
      await _montar(tester, Puerta(session: _SesionFalsa(sesion: false)));

      // Las ligas son privadas: un invitado no ve nada de la app, ni
      // siquiera la portada del club.
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(ClaveScreen), findsNothing);
      expect(find.text('Pasión Futbolera FC'), findsNothing);
    });

    testWidgets('con sesión y sin liga, la clave es lo único que hay',
        (tester) async {
      await _montar(tester, Puerta(session: _SesionFalsa()));
      expect(find.byType(ClaveScreen), findsOneWidget);
      expect(find.text('Las ligas son privadas'), findsOneWidget);
      // La puerta obligatoria no se puede saltar hacia atrás.
      expect(find.byType(BackButton), findsNothing);
    });

    testWidgets('capitán sin equipo ve el paso de fundarlo', (tester) async {
      await _montar(
        tester,
        Puerta(
          session: _SesionFalsa(
            situacionInicial: const MiSituacion(
                tieneGrupo: true, puedeFundar: true, grupo: 'Liga Norte'),
          ),
        ),
      );
      expect(find.text('Estás en Liga Norte'), findsOneWidget);
      expect(find.text('Fundar mi equipo'), findsOneWidget);
    });

    testWidgets('sin equipo y sin poder fundar, se le explica la espera',
        (tester) async {
      await _montar(
        tester,
        Puerta(
          session: _SesionFalsa(
            situacionInicial:
                const MiSituacion(tieneGrupo: true, grupo: 'Liga Norte'),
          ),
        ),
      );
      expect(find.textContaining('todavía sin equipo'), findsOneWidget);
      expect(find.text('Tengo la clave de mi equipo'), findsOneWidget);
    });

    testWidgets('con equipo entra al inicio', (tester) async {
      await _montar(
        tester,
        Puerta(
          session: _SesionFalsa(
            situacionInicial: const MiSituacion(
                tieneGrupo: true, tieneEquipo: true, equipo: 'Halcones FC'),
          ),
        ),
      );
      expect(find.byType(ClaveScreen), findsNothing);
      expect(find.text('Pasión Futbolera FC'), findsOneWidget);
    });
  });

  group('las dos formas de clave no se solapan', () {
    test('ocho caracteres del alfabeto: invitación', () {
      expect(Session.pareceInvitacion('JAEXQUAV'), isTrue);
      expect(Session.pareceInvitacion('jaexquav'), isTrue);
      expect(Session.pareceClaveDev('JAEXQUAV'), isFalse);
    });

    test('doce dígitos o más: clave de dev', () {
      expect(Session.pareceClaveDev('175095967612'), isTrue);
      expect(Session.pareceInvitacion('175095967612'), isFalse);
    });

    test('las invitaciones no cambian: ocho dígitos sigue siendo una', () {
      // El alfabeto incluye del 2 al 9, así que un código puede salir
      // todo en números. Sigue siendo invitación: lo que las separa de
      // una clave de dev es el largo, ocho contra doce.
      expect(Session.pareceInvitacion('48273956'), isTrue);
      expect(Session.pareceClaveDev('48273956'), isFalse);
    });

    test('nada tiene las dos formas a la vez', () {
      for (final c in ['JAEXQUAV', '175095967612', '48273956', 'ABC', '']) {
        expect(Session.pareceInvitacion(c) && Session.pareceClaveDev(c), isFalse,
            reason: '"$c" no puede ser las dos cosas');
      }
    });
  });

  group('ClaveScreen', () {
    testWidgets('dice qué hace la clave antes de canjearla', (tester) async {
      final sesion = _SesionFalsa(claves: {'ABCD2345': _claveCapitan});
      await _montar(tester, ClaveScreen(session: sesion));

      await tester.enterText(find.byType(TextField), 'ABCD2345');
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      expect(
        find.text('Entras a Liga Norte como capitán y podrás fundar tu equipo.'),
        findsOneWidget,
      );
      // Todavía no la canjeó: solo la revisó.
      expect(sesion.canjeadas, isEmpty);
    });

    testWidgets('avisa cuando la clave no sirve, y no deja entrar',
        (tester) async {
      final sesion = _SesionFalsa(claves: {'ZZZZ9999': _claveVencida});
      await _montar(tester, ClaveScreen(session: sesion));

      await tester.enterText(find.byType(TextField), 'ZZZZ9999');
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      expect(find.text('Esa invitación ya venció.'), findsOneWidget);
      final boton = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(boton.onPressed, isNull, reason: 'no debe poder entrar');
    });

    testWidgets('el botón está apagado hasta que la clave esté completa',
        (tester) async {
      await _montar(tester, ClaveScreen(session: _SesionFalsa()));

      var boton = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(boton.onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'ABC');
      await tester.pumpAndSettle(const Duration(milliseconds: 600));
      boton = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(boton.onPressed, isNull);
    });

    testWidgets('deja escribir una clave de dev, que es solo dígitos',
        (tester) async {
      await _montar(tester, ClaveScreen(session: _SesionFalsa()));

      // El campo filtraba al alfabeto del código, que no tiene 1 ni 0.
      // Una clave de dev que empezara con 175 perdía el 1 al teclearla.
      await tester.enterText(find.byType(TextField), '175095967612');
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      final campo = tester.widget<TextField>(find.byType(TextField));
      expect(campo.controller!.text, '175095967612',
          reason: 'la clave de dev tiene que entrar tal cual');
    });

    testWidgets('con una clave de dev el botón se enciende sin revisarla',
        (tester) async {
      final sesion = _SesionFalsa();
      await _montar(tester, ClaveScreen(session: sesion));

      await tester.enterText(find.byType(TextField), '175095967612');
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      // No se consulta al servidor: sería un oráculo de fuerza bruta.
      expect(sesion.revisadas, isEmpty);

      // Y aun así se puede entrar. Antes el botón exigía una revisión
      // válida, que con una clave de dev no llega nunca: quedaba muerto.
      final boton = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(boton.onPressed, isNotNull, reason: 'el botón no puede quedar muerto');

      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(sesion.canjeadas, ['175095967612']);
    });

    testWidgets('la clave de equipo dice a qué equipo entra', (tester) async {
      final sesion = _SesionFalsa(claves: {'EQPT2345': _claveEquipo});
      await _montar(tester, ClaveScreen(session: sesion));

      await tester.enterText(find.byType(TextField), 'EQPT2345');
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      expect(find.text('Te sumas a Halcones FC como jugador.'), findsOneWidget);
      expect(find.text('Entrar a Halcones FC'), findsOneWidget);

      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(sesion.canjeadas, ['EQPT2345']);
      expect(sesion.situacion.tieneEquipo, isTrue);
    });

    testWidgets('una invitación en minúscula sirve igual', (tester) async {
      final sesion = _SesionFalsa(claves: {'ABCD2345': _claveCapitan});
      await _montar(tester, ClaveScreen(session: sesion));

      await tester.enterText(find.byType(TextField), 'abcd2345');
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      // El campo ya no fuerza mayúsculas: hacerlo rompía una clave de
      // dev, que sí las distingue. Normalizar es cosa del servidor, que
      // compara con upper(btrim(code)).
      final campo = tester.widget<TextField>(find.byType(TextField));
      expect(campo.controller!.text, 'abcd2345');
      expect(
        find.text('Entras a Liga Norte como capitán y podrás fundar tu equipo.'),
        findsOneWidget,
      );
    });
  });
}
