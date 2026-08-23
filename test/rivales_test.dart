// Pruebas de rivales, plantilla imaginaria y ranking de goleadores.
//
// El punto que mas importa: lo inventado tiene que verse como inventado.
// Si la app muestra 11 nombres ficticios sin decirlo, esta presentando
// datos falsos como ciertos.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diego_javier_lopez_zambrano/core/session.dart';
import 'package:diego_javier_lopez_zambrano/data/club_admin.dart';
import 'package:diego_javier_lopez_zambrano/models/models.dart';
import 'package:diego_javier_lopez_zambrano/screens/goleadores_screen.dart';
import 'package:diego_javier_lopez_zambrano/screens/rival_plantilla_screen.dart';

class _SesionFalsa extends Session {
  _SesionFalsa({this.rolFalso});
  final TeamRole? rolFalso;

  @override
  bool get hayBackend => true;
  @override
  bool get haySesion => rolFalso != null;
  @override
  TeamRole? get rol => rolFalso;
  @override
  bool get puedeEditarPlantilla => rolFalso?.canEditSquad ?? false;
}

/// ClubAdmin de mentira. Se extiende, no se implementa: asi solo hay que
/// redefinir lo que la prueba usa.
class _AdminFalso extends ClubAdmin {
  _AdminFalso({this.jugadoresRival = const [], this.ranking = const []});

  final List<RivalPlayer> jugadoresRival;
  final List<Goleador> ranking;

  int vecesQueGenero = 0;

  @override
  bool get disponible => true;

  @override
  Future<List<RivalPlayer>> jugadoresRivales(String rivalId) async =>
      jugadoresRival;

  @override
  Future<List<RivalPlayer>> generarPlantillaImaginaria(
    String rivalId, {
    int cantidad = 11,
  }) async {
    vecesQueGenero++;
    return jugadoresRival;
  }

  @override
  Future<List<Goleador>> goleadores({bool soloDelClub = false}) async => ranking;

  @override
  Future<List<GolHistorial>> historialDeGoles() async => const [];
}

RivalPlayer _jugadorRival({
  required String id,
  required String nombre,
  int? dorsal,
  bool inventado = false,
}) =>
    RivalPlayer(
      id: id,
      rivalId: 'r1',
      teamId: 't1',
      fullName: nombre,
      number: dorsal,
      isImaginary: inventado,
    );

const _rival = Rival(id: 'r1', teamId: 't1', name: 'Clásicos FC');

Future<void> _montar(WidgetTester tester, Widget hijo) async {
  tester.view.physicalSize = const Size(1080, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: hijo));
  await tester.pumpAndSettle();
}

void main() {
  group('Rival', () {
    test('sabe si toda su plantilla es inventada', () {
      const inventada = Rival(
          id: 'r1', teamId: 't1', name: 'X', totalJugadores: 11, totalImaginarios: 11);
      const mixta = Rival(
          id: 'r2', teamId: 't1', name: 'Y', totalJugadores: 11, totalImaginarios: 3);
      const vacia = Rival(id: 'r3', teamId: 't1', name: 'Z');

      expect(inventada.plantillaEsInventada, isTrue);
      expect(mixta.plantillaEsInventada, isFalse);
      expect(vacia.plantillaEsInventada, isFalse, reason: 'sin jugadores no es "inventada"');
      expect(vacia.sinPlantilla, isTrue);
    });
  });

  group('Goleador', () {
    test('distingue el bando y arrastra la marca de inventado', () {
      final nuestro = Goleador.fromMap({
        'bando': 'nuestro', 'jugador_id': 'p1', 'nombre': 'Ronny Benítez',
        'dorsal': 9, 'position': 'FW', 'goles': 3, 'es_imaginario': false, 'club': null,
      });
      final rival = Goleador.fromMap({
        'bando': 'rival', 'jugador_id': 'rp1', 'nombre': 'Luis Lucas',
        'dorsal': 9, 'position': 'FW', 'goles': 1, 'es_imaginario': true,
        'club': 'Clásicos FC',
      });

      expect(nuestro.esDelClub, isTrue);
      expect(nuestro.esImaginario, isFalse);
      expect(rival.esDelClub, isFalse);
      expect(rival.esImaginario, isTrue);
      expect(rival.club, 'Clásicos FC');
    });
  });

  group('permisos sobre la plantilla', () {
    test('cualquier integrante puede editarla, el hincha no', () {
      expect(TeamRole.owner.canEditSquad, isTrue);
      expect(TeamRole.admin.canEditSquad, isTrue);
      expect(TeamRole.coach.canEditSquad, isTrue);
      expect(TeamRole.player.canEditSquad, isTrue,
          reason: 'el equipo se administra entre todos sus integrantes');
      expect(TeamRole.viewer.canEditSquad, isFalse);
    });
  });

  group('plantilla del rival', () {
    testWidgets('avisa cuando toda la plantilla es inventada', (tester) async {
      final admin = _AdminFalso(jugadoresRival: [
        for (var i = 1; i <= 11; i++)
          _jugadorRival(id: 'j$i', nombre: 'Inventado $i', dorsal: i, inventado: true),
      ]);

      await _montar(
        tester,
        RivalPlantillaScreen(
          rival: _rival,
          admin: admin,
          session: _SesionFalsa(rolFalso: TeamRole.player),
        ),
      );

      expect(find.text('Esta plantilla es inventada'), findsOneWidget);
      expect(find.textContaining('inventado'), findsWidgets);
    });

    testWidgets('cuenta cuantos son inventados si hay mezcla', (tester) async {
      final admin = _AdminFalso(jugadoresRival: [
        _jugadorRival(id: 'j1', nombre: 'Dato Real', dorsal: 1),
        _jugadorRival(id: 'j2', nombre: 'Inventado A', dorsal: 2, inventado: true),
        _jugadorRival(id: 'j3', nombre: 'Inventado B', dorsal: 3, inventado: true),
      ]);

      await _montar(
        tester,
        RivalPlantillaScreen(
          rival: _rival,
          admin: admin,
          session: _SesionFalsa(rolFalso: TeamRole.coach),
        ),
      );

      expect(find.text('2 de 3 jugadores son inventados'), findsOneWidget);
    });

    testWidgets('sin datos inventados no muestra el aviso', (tester) async {
      final admin = _AdminFalso(jugadoresRival: [
        _jugadorRival(id: 'j1', nombre: 'Dato Real', dorsal: 1),
      ]);

      await _montar(
        tester,
        RivalPlantillaScreen(rival: _rival, admin: admin, session: _SesionFalsa()),
      );

      expect(find.textContaining('inventada'), findsNothing);
      expect(find.text('1 jugadores, todos con datos reales'), findsOneWidget);
    });

    testWidgets('un hincha no ve las opciones de edicion', (tester) async {
      final admin = _AdminFalso(jugadoresRival: [
        _jugadorRival(id: 'j1', nombre: 'Alguien', dorsal: 1, inventado: true),
      ]);

      await _montar(
        tester,
        RivalPlantillaScreen(
          rival: _rival,
          admin: admin,
          session: _SesionFalsa(rolFalso: TeamRole.viewer),
        ),
      );

      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byIcon(Icons.auto_awesome), findsWidgets); // solo la marca
    });

    testWidgets('generar plantilla pide confirmacion antes de reemplazar',
        (tester) async {
      final admin = _AdminFalso(jugadoresRival: [
        _jugadorRival(id: 'j1', nombre: 'Viejo', dorsal: 1, inventado: true),
      ]);

      await _montar(
        tester,
        RivalPlantillaScreen(
          rival: _rival,
          admin: admin,
          session: _SesionFalsa(rolFalso: TeamRole.player),
        ),
      );

      await tester.tap(find.widgetWithIcon(IconButton, Icons.auto_awesome));
      await tester.pumpAndSettle();

      expect(find.text('¿Inventar la plantilla?'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(admin.vecesQueGenero, 0);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.auto_awesome));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inventar'));
      await tester.pumpAndSettle();
      expect(admin.vecesQueGenero, 1);
    });
  });

  group('ranking de goleadores', () {
    testWidgets('separa nuestro club de los rivales y marca lo inventado',
        (tester) async {
      final admin = _AdminFalso(ranking: [
        const Goleador(jugadorId: 'p1', nombre: 'Ronny Benítez', goles: 3, dorsal: 9),
        const Goleador(
          jugadorId: 'rp1',
          nombre: 'Luis Lucas',
          goles: 1,
          dorsal: 9,
          esDelClub: false,
          esImaginario: true,
          club: 'Clásicos FC',
        ),
      ]);

      await _montar(tester, GoleadoresScreen(admin: admin));

      expect(find.text('Nuestro club'), findsOneWidget);
      expect(find.text('Rivales'), findsOneWidget);
      expect(find.text('Ronny Benítez'), findsOneWidget);
      expect(find.text('Luis Lucas'), findsOneWidget);
      // El goleador inventado lleva su marca.
      expect(find.byTooltip('Jugador inventado por falta de datos del rival'),
          findsOneWidget);
    });

    testWidgets('sin goles muestra un estado vacio, no una lista en blanco',
        (tester) async {
      await _montar(tester, GoleadoresScreen(admin: _AdminFalso()));
      expect(find.text('Todavía no hay goles'), findsOneWidget);
    });
  });
}
