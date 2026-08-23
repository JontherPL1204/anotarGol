import 'package:flutter/material.dart';
import 'package:diego_javier_lopez_zambrano/screens/puerta.dart';
import 'package:diego_javier_lopez_zambrano/core/session.dart';
import 'package:diego_javier_lopez_zambrano/core/supabase_service.dart';

Future<void> main() async {
  // Necesario porque hay trabajo asincrono antes de runApp.
  WidgetsFlutterBinding.ensureInitialized();

  // Conecta con Supabase si hay credenciales. Si no las hay, no falla:
  // la app arranca en modo local con los datos de ejemplo.
  await SupabaseService.init();

  // Recupera la sesion guardada, si la hay, antes de pintar. Asi la app
  // no aparece como invitado durante un instante para luego cambiar.
  final session = Session();
  await session.iniciar();

  runApp(MyApp(session: session));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pasión Futbolera',
      theme: ThemeData(
        // Colores personalizados (Punto 2)
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B5E20), // Verde principal
          primary: const Color(0xFF1B5E20),
          secondary: const Color(0xFFFFD700), // Dorado
        ),
        useMaterial3: true,
      ),
      // Puerta decide: sin liga, la clave; con liga, el inicio.
      home: Puerta(session: session),
    );
  }
}
