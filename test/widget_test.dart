// Pruebas de la pantalla principal y la plantilla.
//
// La version original venia del ejemplo del contador de Flutter: buscaba
// un icono `Icons.add` que esta app no tiene y montaba `Homescreen` sin
// `MaterialApp`, asi que no podia pasar.
//
// Ahora las pantallas reciben un `ClubDataSource`, asi que se puede
// probar tanto el modo local (sin backend) como el modo en vivo, sin
// tocar la red ni necesitar un proyecto de Supabase.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diego_javier_lopez_zambrano/data/club_data_source.dart';
import 'package:diego_javier_lopez_zambrano/data/demo_club.dart';
import 'package:diego_javier_lopez_zambrano/homescreen.dart';
import 'package:diego_javier_lopez_zambrano/models/models.dart';

/// Monta la app con una pantalla alta (tipo celular) en vez de los
/// 800x600 por defecto de flutter_test. Sin esto, el boton de calendario
/// queda fuera del viewport y `tap` falla por no poder tocarlo.
Future<void> _montarApp(WidgetTester tester, {ClubDataSource? fuente}) async {
  tester.view.physicalSize = const Size(1080, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // `Homescreen` necesita un `MaterialApp` alrededor: usa `Navigator`,
  // `Theme` y `Directionality`.
  await tester.pumpWidget(
    MaterialApp(
      home: Homescreen(dataSource: fuente ?? const LocalClubDataSource()),
    ),
  );
  // Las cargas son asincronas aunque los datos sean locales.
  await tester.pumpAndSettle();
}

void main() {
  group('modo local (sin backend)', () {
    testWidgets('el marcador arranca en 0 y sube al cantar gol', (tester) async {
      await _montarApp(tester);

      expect(find.text('0'), findsOneWidget);
      expect(find.text('EN VIVO'), findsNothing);

      // Sin backend el contador es de juguete: no escribe en ningún lado,
      // así que no pide autor ni exige partido en juego. Es la entrega
      // académica y tiene que seguir funcionando.
      await tester.tap(find.text('¡CANTAR GOL!'));
      await tester.pump();

      expect(find.text('1'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('el boton de reinicio devuelve el marcador a 0', (tester) async {
      await _montarApp(tester);

      await tester.tap(find.text('¡CANTAR GOL!'));
      await tester.pump();
      await tester.tap(find.text('¡CANTAR GOL!'));
      await tester.pump();
      expect(find.text('2'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();

      // Sin partido en vivo no hay nada que borrar del historial, asi que
      // tampoco hay dialogo de confirmacion.
      expect(find.text('¿Reiniciar el marcador?'), findsNothing);
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('el proximo partido se muestra y se oculta', (tester) async {
      await _montarApp(tester);

      expect(find.textContaining('Próximo encuentro'), findsNothing);

      await tester.tap(find.text('Ver Próximo Partido'));
      await tester.pump();
      expect(find.textContaining('Clásicos FC'), findsOneWidget);

      await tester.tap(find.text('Ocultar Calendario'));
      await tester.pump();
      expect(find.textContaining('Próximo encuentro'), findsNothing);
    });

    testWidgets('la tarjeta del equipo muestra el total real de jugadores',
        (tester) async {
      await _montarApp(tester);

      expect(find.text('Plantilla: ${DemoClub.players.length}'), findsOneWidget);
    });

    testWidgets('desde el inicio se navega a la plantilla', (tester) async {
      await _montarApp(tester);

      await tester.tap(find.text('Plantilla: ${DemoClub.players.length}'));
      await tester.pumpAndSettle();

      expect(find.text('Plantilla del Club'), findsOneWidget);
      expect(find.text('Carlos Navas'), findsOneWidget);
      expect(find.text('11 jugadores'), findsOneWidget);
      // Sin backend, la pantalla avisa que los datos no son reales.
      expect(find.text('Datos de ejemplo'), findsOneWidget);
    });
  });

  group('modo en vivo (con backend)', () {
    testWidgets('muestra el marcador del partido en curso', (tester) async {
      final fuente = _FuenteFalsa();
      addTearDown(fuente.cerrar);

      await _montarApp(tester, fuente: fuente);

      expect(find.text('EN VIVO'), findsOneWidget);
      expect(find.text('1 - 0'), findsOneWidget);
      expect(find.text('vs Clásicos FC'), findsOneWidget);
    });

    testWidgets('cantar gol registra el evento y actualiza el marcador',
        (tester) async {
      final fuente = _FuenteFalsa();
      addTearDown(fuente.cerrar);

      await _montarApp(tester, fuente: fuente);

      final nueve = DemoClub.players.firstWhere((p) => p.number == 9);

      await tester.tap(find.text('¡CANTAR GOL!'));
      await tester.pumpAndSettle();

      // El autor se elige de la plantilla, no escribiendo un dorsal: asi
      // no se le puede anotar un gol a un numero que no existe.
      await tester.tap(find.byType(DropdownButtonFormField<Player>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('9  ${nueve.fullName}').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(fuente.golesRegistrados, 1);
      expect(fuente.ultimoJugadorId, nueve.id);
      expect(fuente.ultimoLado, TeamSide.us);
      expect(find.text('2 - 0'), findsOneWidget);
    });

    testWidgets('registra una tarjeta amarilla con jugador y equipo',
        (tester) async {
      final fuente = _FuenteFalsa();
      addTearDown(fuente.cerrar);

      await _montarApp(tester, fuente: fuente);

      final dos = DemoClub.players.firstWhere((p) => p.number == 2);

      await tester.tap(find.text('Tarjeta'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<Player>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2  ${dos.fullName}').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(fuente.tarjetasRegistradas, 1);
      expect(fuente.ultimoTipo, MatchEventType.yellowCard);
      expect(fuente.ultimoJugadorId, dos.id);
    });

    testWidgets('un gol del rival se le anota a un jugador del rival',
        (tester) async {
      final fuente = _FuenteFalsa();
      addTearDown(fuente.cerrar);
      // Con la plantilla del rival cargada se puede decir quien anoto.
      // Sin ella el gol contaria igual, pero sin autor.
      fuente.rivalesCargados = const [
        RivalPlayer(
          id: 'rp-9',
          rivalId: 'r1',
          teamId: 't1',
          fullName: 'Delantero Rival',
          number: 9,
        ),
      ];

      await _montarApp(tester, fuente: fuente);

      await tester.tap(find.text('¡CANTAR GOL!'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<TeamSide>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rival FC').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<RivalPlayer>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('9  Delantero Rival').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(fuente.ultimoLado, TeamSide.them);
      expect(fuente.ultimoRivalId, 'rp-9');
      // Y nunca se mezcla: un gol del rival no lleva jugador nuestro.
      expect(fuente.ultimoJugadorId, isNull);
    });

    testWidgets('el reloj ofrece solo el paso siguiente', (tester) async {
      final fuente = _FuenteFalsa();
      addTearDown(fuente.cerrar);
      fuente.reloj = PartidoVivo(
        id: 'm1',
        teamId: 't1',
        equipo: 'Pasión Futbolera FC',
        rival: 'Rival FC',
        fase: FasePartido.listoParaEmpezar,
        kickoffAt: DateTime(2026, 8, 25, 20),
      );

      await _montarApp(tester, fuente: fuente);

      // Sin empezar no se puede anotar: la base rechazaría el evento.
      final gol = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, '¡CANTAR GOL!'),
      );
      expect(gol.onPressed, isNull);

      expect(find.text('Empezar partido'), findsOneWidget);
      expect(find.text('Terminar partido'), findsNothing);

      await tester.tap(find.text('Empezar partido'));
      await tester.pumpAndSettle();

      expect(fuente.pasosDelReloj, ['iniciar']);
      expect(find.text('Ir al descanso'), findsOneWidget);
      expect(find.text('Empezar partido'), findsNothing);
    });

    testWidgets('el marcador se actualiza desde el tiempo real',
        (tester) async {
      final fuente = _FuenteFalsa();
      addTearDown(fuente.cerrar);

      await _montarApp(tester, fuente: fuente);
      expect(find.text('1 - 0'), findsOneWidget);

      // Simula un gol anotado desde otro dispositivo.
      fuente.emitir(fuente.partidoCon(golesPropios: 1, golesRival: 1));
      await tester.pumpAndSettle();

      expect(find.text('1 - 1'), findsOneWidget);
    });

    testWidgets('reiniciar pide confirmacion porque borra historial',
        (tester) async {
      final fuente = _FuenteFalsa();
      addTearDown(fuente.cerrar);

      await _montarApp(tester, fuente: fuente);

      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();
      expect(find.text('¿Reiniciar el marcador?'), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(fuente.golesBorrados, isFalse);

      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Borrar goles'));
      await tester.pumpAndSettle();
      expect(fuente.golesBorrados, isTrue);
    });
  });
}

/// Fuente de datos de mentira con un partido en vivo. No toca red.
class _FuenteFalsa implements ClubDataSource {
  _FuenteFalsa();

  final _cambios = StreamController<FootballMatch?>.broadcast();

  int golesRegistrados = 0;
  int tarjetasRegistradas = 0;
  String? ultimoJugadorId;
  String? ultimoRivalId;
  MatchEventType? ultimoTipo;
  TeamSide? ultimoLado;
  bool golesBorrados = false;
  List<RivalPlayer> rivalesCargados = const [];

  late FootballMatch _partido = partidoCon(golesPropios: 1, golesRival: 0);

  FootballMatch partidoCon({
    required int golesPropios,
    required int golesRival,
  }) =>
      FootballMatch(
        id: 'm1',
        teamId: 't1',
        teamName: 'Pasión Futbolera FC',
        opponentName: 'Clásicos FC',
        kickoffAt: DateTime(2026, 8, 23, 16),
        status: MatchStatus.live,
        teamScore: golesPropios,
        opponentScore: golesRival,
      );

  void emitir(FootballMatch partido) => _cambios.add(partido);
  Future<void> cerrar() => _cambios.close();

  @override
  bool get isRemote => true;

  @override
  Future<List<Player>> fetchPlayers() async => DemoClub.players;

  @override
  Future<FootballMatch?> fetchNextMatch() async => _partido;

  @override
  Future<FootballMatch?> fetchLiveMatch() async => _partido;

  @override
  Future<List<MatchEvent>> fetchEvents(String matchId) async => const [];

  @override
  Future<FootballMatch?> logGoal(
    String matchId, {
    String? playerId,
    String? rivalPlayerId,
    TeamSide side = TeamSide.us,
  }) async {
    golesRegistrados++;
    ultimoJugadorId = playerId;
    ultimoRivalId = rivalPlayerId;
    ultimoLado = side;
    _partido = partidoCon(
      golesPropios: _partido.teamScore + 1,
      golesRival: _partido.opponentScore,
    );
    return _partido;
  }

  @override
  Future<void> logCard(
    String matchId, {
    required MatchEventType type,
    String? playerId,
    String? rivalPlayerId,
    TeamSide side = TeamSide.us,
  }) async {
    tarjetasRegistradas++;
    ultimoTipo = type;
    ultimoJugadorId = playerId;
    ultimoRivalId = rivalPlayerId;
    ultimoLado = side;
  }

  // El reloj. `fase` decide qué botones tienen sentido y si la base
  // aceptaría un evento.
  PartidoVivo? reloj = PartidoVivo(
    id: 'm1',
    teamId: 't1',
    equipo: 'Pasión Futbolera FC',
    rival: 'Rival FC',
    fase: FasePartido.primerTiempo,
    kickoffAt: DateTime(2026, 8, 25, 20),
    minuto: 12,
  );
  final List<String> pasosDelReloj = [];

  @override
  Future<PartidoVivo?> partidoDelDia() async => reloj;

  @override
  Future<List<RivalPlayer>> fetchRivalPlayers(String matchId) async =>
      rivalesCargados;

  @override
  Future<void> iniciarPartido(String matchId) async {
    pasosDelReloj.add('iniciar');
    reloj = _conFase(FasePartido.primerTiempo);
  }

  @override
  Future<void> irAlDescanso(String matchId) async {
    pasosDelReloj.add('descanso');
    reloj = _conFase(FasePartido.descanso);
  }

  @override
  Future<void> iniciarSegundoTiempo(String matchId) async {
    pasosDelReloj.add('segundo');
    reloj = _conFase(FasePartido.segundoTiempo);
  }

  @override
  Future<void> finalizarPartido(String matchId, {int agregados = 0}) async {
    pasosDelReloj.add('terminar');
    reloj = _conFase(FasePartido.terminado);
  }

  PartidoVivo _conFase(FasePartido f) => PartidoVivo(
        id: reloj?.id ?? 'm1',
        teamId: 't1',
        equipo: 'Pasión Futbolera FC',
        rival: 'Rival FC',
        fase: f,
        kickoffAt: DateTime(2026, 8, 25, 20),
        minuto: f.enJuego ? 10 : null,
      );

  @override
  Future<void> clearGoals(String matchId) async {
    golesBorrados = true;
  }

  @override
  Stream<FootballMatch?> watchMatch(String matchId) => _cambios.stream;
}
