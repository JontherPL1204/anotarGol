// Pruebas de sesion, permisos y pantalla de login.
//
// Ninguna toca red: se usa una `Session` falsa que simula tener (o no)
// backend y rol. Lo que se verifica es la regla de negocio que la app
// comparte con RLS: sin rol de cuerpo tecnico no se puede anotar.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diego_javier_lopez_zambrano/core/session.dart';
import 'package:diego_javier_lopez_zambrano/data/club_data_source.dart';
import 'package:diego_javier_lopez_zambrano/homescreen.dart';
import 'package:diego_javier_lopez_zambrano/models/models.dart';
import 'package:diego_javier_lopez_zambrano/screens/login_screen.dart';
import 'package:diego_javier_lopez_zambrano/widgets/marcador_card.dart';

/// Sesion de mentira: no habla con Supabase.
class _SesionFalsa extends Session {
  _SesionFalsa({
    this.backend = true,
    TeamRole? rolInicial,
    this.errorAlEntrar,
  }) : _rolFalso = rolInicial;

  final bool backend;
  final String? errorAlEntrar;
  TeamRole? _rolFalso;
  bool _entro = false;

  int intentosDeEntrar = 0;
  bool reclamoElClub = false;

  @override
  bool get hayBackend => backend;

  @override
  bool get haySesion => _entro;

  @override
  TeamRole? get rol => _rolFalso;

  @override
  bool get puedeEditar => _rolFalso?.canEdit ?? false;

  @override
  String get nombre => 'Jonther';

  @override
  Future<String?> entrar({required String correo, required String clave}) async {
    intentosDeEntrar++;
    if (!backend) return 'La app está en modo local: no hay servidor configurado.';
    if (errorAlEntrar != null) return errorAlEntrar;
    _entro = true;
    _rolFalso = TeamRole.coach;
    notifyListeners();
    return null;
  }

  @override
  Future<String?> reclamarClub() async {
    reclamoElClub = true;
    _rolFalso = TeamRole.owner;
    notifyListeners();
    return null;
  }
}

/// Fuente con un partido en vivo, para probar los permisos del marcador.
class _FuenteEnVivo implements ClubDataSource {
  int golesRegistrados = 0;

  final _partido = FootballMatch(
    id: 'm1',
    teamId: 't1',
    teamName: 'Pasión Futbolera FC',
    opponentName: 'Clásicos FC',
    kickoffAt: DateTime(2026, 8, 30, 16),
    status: MatchStatus.live,
    teamScore: 1,
  );

  @override
  bool get isRemote => true;
  @override
  Future<List<Player>> fetchPlayers() async => const [];
  @override
  Future<FootballMatch?> fetchNextMatch() async => _partido;
  @override
  Future<FootballMatch?> fetchLiveMatch() async => _partido;
  @override
  Future<List<MatchEvent>> fetchEvents(String matchId) async => const [];
  @override
  Future<FootballMatch?> logGoal(String matchId) async {
    golesRegistrados++;
    return _partido;
  }
  @override
  Future<void> clearGoals(String matchId) async {}
  @override
  Stream<FootballMatch?> watchMatch(String matchId) => const Stream.empty();
}

Future<void> _montar(WidgetTester tester, Widget hijo) async {
  tester.view.physicalSize = const Size(1080, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: hijo));
  await tester.pumpAndSettle();
}

void main() {
  group('Session', () {
    test('sin backend, entrar avisa que la app esta en modo local', () async {
      final sesion = _SesionFalsa(backend: false);
      final error = await sesion.entrar(correo: 'a@b.com', clave: '123456');
      expect(error, contains('modo local'));
      expect(sesion.haySesion, isFalse);
    });

    test('un rol de hincha no puede editar', () {
      expect(_SesionFalsa(rolInicial: TeamRole.viewer).puedeEditar, isFalse);
      expect(_SesionFalsa(rolInicial: TeamRole.player).puedeEditar, isFalse);
    });

    test('cuerpo tecnico y superiores pueden editar', () {
      expect(_SesionFalsa(rolInicial: TeamRole.coach).puedeEditar, isTrue);
      expect(_SesionFalsa(rolInicial: TeamRole.admin).puedeEditar, isTrue);
      expect(_SesionFalsa(rolInicial: TeamRole.owner).puedeEditar, isTrue);
    });

    test('solo admin y owner administran el club', () {
      expect(TeamRole.coach.canAdmin, isFalse);
      expect(TeamRole.admin.canAdmin, isTrue);
      expect(TeamRole.owner.canAdmin, isTrue);
    });
  });

  group('permisos sobre el marcador en vivo', () {
    testWidgets('sin rol, el boton de gol queda bloqueado y se explica',
        (tester) async {
      final fuente = _FuenteEnVivo();
      await _montar(
        tester,
        Scaffold(
          body: MarcadorCard(dataSource: fuente, session: _SesionFalsa()),
        ),
      );

      expect(find.text('Solo el cuerpo técnico puede anotar'), findsOneWidget);

      final boton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, '¡CANTAR GOL!'),
      );
      expect(boton.onPressed, isNull, reason: 'debe estar deshabilitado');

      await tester.tap(find.text('¡CANTAR GOL!'));
      await tester.pump();
      expect(fuente.golesRegistrados, 0);
    });

    testWidgets('con rol de cuerpo tecnico, el gol se registra',
        (tester) async {
      final fuente = _FuenteEnVivo();
      await _montar(
        tester,
        Scaffold(
          body: MarcadorCard(
            dataSource: fuente,
            session: _SesionFalsa(rolInicial: TeamRole.coach),
          ),
        ),
      );

      expect(find.text('Solo el cuerpo técnico puede anotar'), findsNothing);

      await tester.tap(find.text('¡CANTAR GOL!'));
      await tester.pumpAndSettle();
      expect(fuente.golesRegistrados, 1);
    });
  });

  group('LoginScreen', () {
    testWidgets('no envia el formulario con campos vacios', (tester) async {
      final sesion = _SesionFalsa();
      await _montar(tester, LoginScreen(session: sesion));

      await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
      await tester.pumpAndSettle();

      expect(find.text('Escribe tu correo'), findsOneWidget);
      expect(find.text('Escribe tu contraseña'), findsOneWidget);
      expect(sesion.intentosDeEntrar, 0);
    });

    testWidgets('rechaza un correo sin arroba', (tester) async {
      final sesion = _SesionFalsa();
      await _montar(tester, LoginScreen(session: sesion));

      await tester.enterText(find.byType(TextFormField).first, 'noesuncorreo');
      await tester.enterText(find.byType(TextFormField).last, '123456');
      await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
      await tester.pumpAndSettle();

      expect(find.text('Ese correo no parece válido'), findsOneWidget);
      expect(sesion.intentosDeEntrar, 0);
    });

    testWidgets('muestra el error que devuelve el servidor', (tester) async {
      final sesion = _SesionFalsa(errorAlEntrar: 'Correo o contraseña incorrectos.');
      await _montar(tester, LoginScreen(session: sesion));

      await tester.enterText(find.byType(TextFormField).first, 'jonther@club.com');
      await tester.enterText(find.byType(TextFormField).last, 'malaclave');
      await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
      await tester.pumpAndSettle();

      expect(sesion.intentosDeEntrar, 1);
      expect(find.text('Correo o contraseña incorrectos.'), findsOneWidget);
    });

    testWidgets('alterna entre entrar y crear cuenta', (tester) async {
      await _montar(tester, LoginScreen(session: _SesionFalsa()));

      expect(find.widgetWithText(FilledButton, 'Entrar'), findsOneWidget);

      await tester.tap(find.text('¿No tienes cuenta? Créala'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, 'Crear cuenta'), findsOneWidget);
      expect(find.text('Tu nombre (opcional)'), findsOneWidget);
    });
  });

  group('acceso desde la pantalla principal', () {
    testWidgets('como invitado ofrece iniciar sesion', (tester) async {
      await _montar(
        tester,
        Homescreen(
          dataSource: const LocalClubDataSource(),
          session: _SesionFalsa(),
        ),
      );

      expect(find.byIcon(Icons.login), findsOneWidget);
      expect(find.byIcon(Icons.account_circle), findsNothing);

      await tester.tap(find.byIcon(Icons.login));
      await tester.pumpAndSettle();
      expect(find.text('Iniciar sesión'), findsWidgets);
    });

    testWidgets('tras entrar, el icono pasa a ser el de la cuenta',
        (tester) async {
      final sesion = _SesionFalsa();
      await _montar(
        tester,
        Homescreen(dataSource: const LocalClubDataSource(), session: sesion),
      );

      await sesion.entrar(correo: 'jonther@club.com', clave: '123456');
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.account_circle), findsOneWidget);
      expect(find.byIcon(Icons.login), findsNothing);
    });
  });
}
