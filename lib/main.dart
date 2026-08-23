import 'package:flutter/material.dart';
import 'package:diego_javier_lopez_zambrano/homescreen.dart';
import 'package:diego_javier_lopez_zambrano/core/supabase_service.dart';

Future<void> main() async {
  // Necesario porque hay trabajo asincrono antes de runApp.
  WidgetsFlutterBinding.ensureInitialized();

  // Conecta con Supabase si hay credenciales. Si no las hay, no falla:
  // la app arranca en modo local con los datos de ejemplo.
  await SupabaseService.init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
      home: const Homescreen(),
    );
  }
}
