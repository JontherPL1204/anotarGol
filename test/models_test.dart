// Pruebas de los modelos. Son Dart puro: no tocan red ni base de datos,
// asi que corren en milisegundos y sirven de red de seguridad para las
// reglas de negocio que comparten app y Postgres.

import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

import 'package:diego_javier_lopez_zambrano/models/models.dart';

void main() {
  group('MatchEvent', () {
    MatchEvent gol({
      TeamSide side = TeamSide.us,
      bool enPropiaPuerta = false,
    }) =>
        MatchEvent(
          id: 'e1',
          matchId: 'm1',
          teamId: 't1',
          type: MatchEventType.goal,
          side: side,
          isOwnGoal: enPropiaPuerta,
        );

    test('un gol normal suma para el lado que lo anota', () {
      expect(gol().scoringSide, TeamSide.us);
      expect(gol(side: TeamSide.them).scoringSide, TeamSide.them);
    });

    test('un autogol suma para el rival', () {
      expect(gol(enPropiaPuerta: true).scoringSide, TeamSide.them);
      expect(
        gol(side: TeamSide.them, enPropiaPuerta: true).scoringSide,
        TeamSide.us,
      );
    });

    test('un evento que no es gol no suma para nadie', () {
      const amarilla = MatchEvent(
        id: 'e2',
        matchId: 'm1',
        teamId: 't1',
        type: MatchEventType.yellowCard,
      );
      expect(amarilla.scoringSide, isNull);
    });

    test('los tipos viajan a Postgres en snake_case', () {
      expect(MatchEventType.yellowCard.wire, 'yellow_card');
      expect(MatchEventType.parse('yellow_card'), MatchEventType.yellowCard);
    });

    test('un tipo desconocido no rompe la app', () {
      expect(MatchEventType.parse('bicicleta'), MatchEventType.note);
      expect(MatchStatus.parse(null), MatchStatus.scheduled);
    });
  });

  group('FootballMatch', () {
    FootballMatch partido({required bool deLocal}) => FootballMatch(
          id: 'm1',
          teamId: 't1',
          teamName: 'Pasión Futbolera FC',
          opponentName: 'Clásicos FC',
          kickoffAt: DateTime(2026, 8, 23, 16),
          isHome: deLocal,
          teamScore: 2,
          opponentScore: 1,
        );

    test('de local, nuestro marcador va primero', () {
      final m = partido(deLocal: true);
      expect(m.homeName, 'Pasión Futbolera FC');
      expect(m.scoreLabel, '2 - 1');
    });

    test('de visita, el marcador se invierte al mostrarlo', () {
      final m = partido(deLocal: false);
      expect(m.homeName, 'Clásicos FC');
      expect(m.awayName, 'Pasión Futbolera FC');
      expect(m.scoreLabel, '1 - 2');
    });
  });

  group('Player', () {
    test('usa el detalle de posicion cuando existe', () {
      const p = Player(
        id: 'p1',
        teamId: 't1',
        fullName: 'Carlos Navas',
        number: 1,
        position: PlayerPosition.gk,
        positionDetail: 'Portero',
      );
      expect(p.positionLabel, 'Portero');
      expect(p.shirtLabel, '1');
    });

    test('cae a la etiqueta generica si no hay detalle', () {
      const p = Player(id: 'p2', teamId: 't1', fullName: 'Sin Dorsal');
      expect(p.positionLabel, 'Mediocampista');
      expect(p.shirtLabel, '-');
    });
  });

  group('Team', () {
    test('convierte el color hexadecimal del club', () {
      const t = Team(id: 't1', name: 'PFC', primaryColorHex: '#1B5E20');
      expect(t.primaryColor, const Color(0xFF1B5E20));
    });

    test('un hexadecimal invalido cae al verde por defecto', () {
      const t = Team(id: 't1', name: 'PFC', primaryColorHex: 'no-es-color');
      expect(t.primaryColor, const Color(0xFF1B5E20));
    });
  });
}
