// Pruebas del panel de desarrollo.
//
// Lo que más importa verificar aquí es lo que la pantalla le dice al
// usuario ANTES de que escriba nada: una clave válida convierte la
// cuenta en cuenta de dev, con poder total sobre la plataforma. Si ese
// aviso desaparece, alguien puede canjear una clave sin saber qué está
// aceptando.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diego_javier_lopez_zambrano/models/models.dart';
import 'package:diego_javier_lopez_zambrano/repositories/repositories.dart';
import 'package:diego_javier_lopez_zambrano/screens/dev_acceso_screen.dart';
import 'package:diego_javier_lopez_zambrano/screens/dev_panel_screen.dart';

class _DevFalso extends DevRepository {
  _DevFalso({
    this.estadoInicial = const PanelDev(),
    this.ligas_ = const [],
    this.equipos_ = const [],
  });

  PanelDev estadoInicial;

  /// La unica clave que esta falsa acepta.
  static const claveBuena = 'LaClaveMaestra2026';
  final List<GrupoDev> ligas_;
  final List<EquipoDev> equipos_;

  final List<String> canjes = [];
  final List<String> aperturas = [];
  int intentosFallidos = 0;
  bool cerrado = false;
  String? ligaBorrada;
  String? claveGeneradaPara;

  @override
  Future<PanelDev> estado() async => estadoInicial;

  @override
  Future<ResultadoClave> canjearClaveDev(String codigo) async {
    canjes.add(codigo);
    if (codigo != claveBuena) {
      intentosFallidos++;
      estadoInicial = PanelDev(intentos: intentosFallidos);
      return const ResultadoClave(ok: false, motivo: 'Clave incorrecta.');
    }
    estadoInicial = PanelDev(soyDev: true, abierto: true);
    return ResultadoClave(ok: true, expira: DateTime.now().add(const Duration(minutes: 30)));
  }

  @override
  Future<ResultadoClave> abrirPanel({String? codigo, int minutos = 30}) async {
    aperturas.add(codigo ?? '');
    if (codigo != claveBuena) {
      return const ResultadoClave(ok: false, motivo: 'Clave incorrecta.');
    }
    estadoInicial = const PanelDev(soyDev: true, hayClave: true, abierto: true);
    return ResultadoClave(ok: true, expira: DateTime.now().add(const Duration(minutes: 30)));
  }

  @override
  Future<void> cerrarPanel() async => cerrado = true;

  @override
  Future<List<GrupoDev>> ligas() async => ligas_;

  @override
  Future<List<EquipoDev>> equipos({String? groupId}) async => equipos_;

  @override
  Future<String> claveDeCapitan({
    required String groupId,
    int? maxUsos = 1,
    int? dias,
  }) async {
    claveGeneradaPara = groupId;
    return 'ABCD2345';
  }

  @override
  Future<void> borrarLiga(String groupId) async => ligaBorrada = groupId;
}

Future<void> _montar(WidgetTester tester, Widget hijo) async {
  tester.view.physicalSize = const Size(1080, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: hijo));
  await tester.pumpAndSettle();
}

const _liga = GrupoDev(
  id: 'g1',
  name: 'Liga de Prueba',
  equipos: 2,
  miembros: 5,
  partidos: 3,
);

const _equipoListo = EquipoDev(
  id: 't1',
  groupId: 'g1',
  etiqueta: 'Equipo 1 (Halcones FC)',
  nombre: 'Halcones FC',
  numero: 1,
  jugadores: 11,
  conCedula: 11,
  tieneCapitan: true,
  habilitado: true,
);

const _equipoIncompleto = EquipoDev(
  id: 't2',
  groupId: 'g1',
  etiqueta: 'Equipo 2 (Tiburones FC)',
  nombre: 'Tiburones FC',
  numero: 2,
  jugadores: 7,
  conCedula: 7,
  tieneCapitan: false,
);

void main() {
  group('PanelDev', () {
    test('sabe si está bloqueado por intentos', () {
      final bloqueado = PanelDev(
        soyDev: true,
        bloqueadoHasta: DateTime.now().add(const Duration(minutes: 10)),
      );
      final vencido = PanelDev(
        soyDev: true,
        bloqueadoHasta: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      expect(bloqueado.bloqueado, isTrue);
      expect(vencido.bloqueado, isFalse);
    });

    test('el tiempo restante solo cuenta con el panel abierto', () {
      final abierto = PanelDev(
        soyDev: true,
        abierto: true,
        expiraAt: DateTime.now().add(const Duration(minutes: 20)),
      );
      final cerrado = PanelDev(
        soyDev: true,
        expiraAt: DateTime.now().add(const Duration(minutes: 20)),
      );
      expect(abierto.restante!.inMinutes, greaterThan(18));
      expect(cerrado.restante, isNull);
    });
  });

  group('EquipoDev', () {
    test('cuenta lo que falta para los 11', () {
      expect(_equipoIncompleto.faltan, 4);
      expect(_equipoListo.faltan, 0);
    });
  });

  group('DevAccesoScreen', () {
    testWidgets('a quien no es dev le advierte qué está aceptando',
        (tester) async {
      await _montar(tester, DevAccesoScreen(dev: _DevFalso()));

      expect(find.text('¿Tienes una clave de acceso?'), findsOneWidget);
      expect(
        find.textContaining('convierte esta cuenta en cuenta de desarrollo'),
        findsOneWidget,
        reason: 'sin este aviso, alguien canjea sin saber qué acepta',
      );
      expect(find.text('Canjear la clave'), findsOneWidget);
    });

    testWidgets('a quien ya es dev solo le ofrece abrir el panel',
        (tester) async {
      await _montar(
        tester,
        DevAccesoScreen(
          dev: _DevFalso(
            estadoInicial: const PanelDev(soyDev: true, hayClave: true),
          ),
        ),
      );

      expect(find.text('Panel de desarrollo'), findsOneWidget);
      expect(find.text('Abrir el panel'), findsWidgets);
      expect(
        find.textContaining('convierte esta cuenta'),
        findsNothing,
        reason: 'ya es dev: no hay nada que advertirle',
      );
    });

    testWidgets('una clave incorrecta muestra el motivo, no un error crudo',
        (tester) async {
      final dev = _DevFalso();
      await _montar(tester, DevAccesoScreen(dev: dev));

      await tester.enterText(find.byType(TextField), 'lo-que-sea');
      await tester.tap(find.text('Canjear la clave'));
      await tester.pumpAndSettle();

      expect(find.text('Clave incorrecta.'), findsOneWidget);
      expect(dev.canjes, ['lo-que-sea']);
    });

    testWidgets('muestra cuántos intentos van', (tester) async {
      final dev = _DevFalso(estadoInicial: const PanelDev(intentos: 3));
      await _montar(tester, DevAccesoScreen(dev: dev));
      expect(find.text('Intentos fallidos: 3 de 5'), findsOneWidget);
    });

    testWidgets('bloqueado no deja ni escribir', (tester) async {
      await _montar(
        tester,
        DevAccesoScreen(
          dev: _DevFalso(
            estadoInicial: PanelDev(
              soyDev: true,
              bloqueadoHasta: DateTime.now().add(const Duration(minutes: 10)),
            ),
          ),
        ),
      );

      expect(find.textContaining('Demasiados intentos'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('con el panel ya abierto entra directo', (tester) async {
      await _montar(
        tester,
        DevAccesoScreen(
          dev: _DevFalso(
            estadoInicial: const PanelDev(soyDev: true, abierto: true),
          ),
        ),
      );
      expect(find.byType(DevPanelScreen), findsOneWidget);
    });
  });

  group('DevPanelScreen', () {
    testWidgets('sin ligas lo dice en vez de mostrar una lista vacía',
        (tester) async {
      await _montar(tester, DevPanelScreen(dev: _DevFalso()));
      expect(find.text('Todavía no hay ligas'), findsOneWidget);
    });

    testWidgets('lista las ligas con sus equipos numerados', (tester) async {
      final dev = _DevFalso(
        estadoInicial: const PanelDev(soyDev: true, abierto: true),
        ligas_: const [_liga],
        equipos_: const [_equipoListo, _equipoIncompleto],
      );
      await _montar(tester, DevPanelScreen(dev: dev));

      expect(find.text('Liga de Prueba'), findsOneWidget);
      expect(find.textContaining('2 equipos'), findsOneWidget);

      await tester.tap(find.text('Liga de Prueba'));
      await tester.pumpAndSettle();

      // La etiqueta con número es lo que distingue la vista del dev.
      expect(find.text('Equipo 1 (Halcones FC)'), findsOneWidget);
      expect(find.text('Equipo 2 (Tiburones FC)'), findsOneWidget);
      expect(find.textContaining('listo para jugar'), findsOneWidget);
      expect(find.textContaining('Faltan 4 con cédula'), findsOneWidget);
      expect(find.textContaining('sin capitán'), findsOneWidget);
    });

    testWidgets('genera la clave de capitán de una liga', (tester) async {
      final dev = _DevFalso(
        estadoInicial: const PanelDev(soyDev: true, abierto: true),
        ligas_: const [_liga],
      );
      await _montar(tester, DevPanelScreen(dev: dev));

      await tester.tap(find.text('Liga de Prueba'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clave de capitán'));
      await tester.pumpAndSettle();

      expect(dev.claveGeneradaPara, 'g1');
      expect(find.text('ABCD2345'), findsOneWidget);
      expect(find.textContaining('un solo uso'), findsOneWidget);
    });

    testWidgets('borrar una liga exige escribir su nombre', (tester) async {
      final dev = _DevFalso(
        estadoInicial: const PanelDev(soyDev: true, abierto: true),
        ligas_: const [_liga],
      );
      await _montar(tester, DevPanelScreen(dev: dev));

      await tester.tap(find.text('Liga de Prueba'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Borrar'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Se lleva por delante'), findsOneWidget);

      // Con el botón apagado hasta que el nombre coincida: un borrado en
      // cascada no puede estar a un toque de distancia.
      var boton = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Borrar'));
      expect(boton.onPressed, isNull);
      expect(dev.ligaBorrada, isNull);

      await tester.enterText(find.byType(TextField).last, 'Liga equivocada');
      await tester.pumpAndSettle();
      boton = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Borrar'));
      expect(boton.onPressed, isNull);

      await tester.enterText(find.byType(TextField).last, 'Liga de Prueba');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Borrar'));
      await tester.pumpAndSettle();

      expect(dev.ligaBorrada, 'g1');
    });

    testWidgets('avisa cuánto le queda abierto', (tester) async {
      final dev = _DevFalso(
        estadoInicial: PanelDev(
          soyDev: true,
          abierto: true,
          expiraAt: DateTime.now().add(const Duration(minutes: 25)),
        ),
        ligas_: const [_liga],
      );
      await _montar(tester, DevPanelScreen(dev: dev));
      expect(find.textContaining('Se cierra solo en'), findsOneWidget);
    });

    testWidgets('el candado cierra el panel', (tester) async {
      final dev = _DevFalso(
        estadoInicial: const PanelDev(soyDev: true, abierto: true),
        ligas_: const [_liga],
      );
      await _montar(tester, DevPanelScreen(dev: dev));

      await tester.tap(find.byIcon(Icons.lock));
      await tester.pumpAndSettle();
      expect(dev.cerrado, isTrue);
    });
  });
}
