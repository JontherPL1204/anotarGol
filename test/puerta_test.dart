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

  @override
  bool get hayBackend => backend;

  @override
  bool get haySesion => sesion;

  @override
  Future<ClaveRevisada> revisarClave(String codigo) async =>
      claves[codigo.toUpperCase()] ??
      const ClaveRevisada(valida: false, motivo: 'Esa clave no existe.');

  @override
  Future<String?> canjearClave(String codigo) async {
    canjeadas.add(codigo.toUpperCase());
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

    testWidgets('como invitado tampoco pide clave', (tester) async {
      await _montar(tester, Puerta(session: _SesionFalsa(sesion: false)));
      expect(find.byType(ClaveScreen), findsNothing);
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

    testWidgets('descarta letras que el alfabeto del código no admite',
        (tester) async {
      await _montar(tester, ClaveScreen(session: _SesionFalsa()));

      // El alfabeto excluye O/0 e I/1 para poder dictar el código en voz
      // alta. Si el usuario los teclea, se descartan.
      await tester.enterText(find.byType(TextField), 'IOAB2345');
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      final campo = tester.widget<TextField>(find.byType(TextField));
      expect(campo.controller!.text, 'AB2345',
          reason: 'la I y la O se descartan');
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

    testWidgets('escribe en mayúscula aunque se teclee en minúscula',
        (tester) async {
      final sesion = _SesionFalsa(claves: {'ABCD2345': _claveCapitan});
      await _montar(tester, ClaveScreen(session: sesion));

      await tester.enterText(find.byType(TextField), 'abcd2345');
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      final campo = tester.widget<TextField>(find.byType(TextField));
      expect(campo.controller!.text, 'ABCD2345');
    });
  });
}
