import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/session.dart';
import '../homescreen.dart';
import 'clave_screen.dart';
import 'dev_panel_screen.dart';
import 'elegir_liga_screen.dart';
import 'fundar_equipo_screen.dart';

/// Decide qué pantalla ve el usuario al abrir la app.
///
/// La regla es la del modelo de privacidad: sin liga no hay nada que
/// mostrar. Por eso quien inicia sesión y no pertenece a ninguna cae
/// directo en la casilla de la clave, y no puede saltarla.
///
/// Sin backend configurado no hay nada de esto: la app arranca en modo
/// local con los datos de ejemplo, como siempre.
class Puerta extends StatelessWidget {
  const Puerta({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        // Modo local o invitado: la app funciona como demo.
        if (!session.hayBackend || !session.haySesion) {
          return Homescreen(session: session);
        }

        // Con sesión pero sin liga: la clave es lo único que hay.
        if (session.situacion.necesitaClave) {
          return ClaveScreen(session: session);
        }

        // El dev no pertenece a ninguna liga por diseño: exigirle una
        // clave de liga lo dejaría atrapado. Entra directo a su panel.
        if (session.esDev && !session.situacion.tieneGrupo) {
          return const DevPanelScreen();
        }

        // Con varias ligas, lo primero es saber en cuál trabaja.
        if (session.debeElegirGrupo) {
          return ElegirLigaScreen(session: session);
        }

        // Entró con clave de capitán y todavía no armó su equipo.
        if (session.situacion.debeFundarEquipo) {
          return _FundarEquipo(session: session);
        }

        // En la liga pero sin equipo y sin poder fundar: alguien tiene
        // que ficharlo. Decírselo es mejor que mostrarle un inicio vacío.
        if (session.situacion.esperaQueLoFichen) {
          return _EsperandoFicha(session: session);
        }

        return Homescreen(session: session);
      },
    );
  }
}

/// Entró como capitán pero su equipo no existe todavía.
class _FundarEquipo extends StatelessWidget {
  const _FundarEquipo({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final s = session.situacion;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.grupo ?? 'Tu liga',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1B5E20),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: session.salir,
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_moderator, size: 64, color: Color(0xFF1B5E20)),
              const SizedBox(height: 20),
              Text(
                'Estás en ${s.grupo}',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                'Entraste con clave de capitán, así que el siguiente paso es '
                'fundar tu equipo y cargar a tus 11 jugadores con su cédula.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: s.groupId == null
                    ? null
                    : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FundarEquipoScreen(
                              session: session,
                              groupId: s.groupId!,
                            ),
                          ),
                        ),
                icon: const Icon(Icons.shield),
                label: const Text('Fundar mi equipo'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1B5E20),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Está en la liga pero nadie lo fichó todavía.
class _EsperandoFicha extends StatelessWidget {
  const _EsperandoFicha({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final s = session.situacion;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.grupo ?? 'Tu liga',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1B5E20),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: session.salir,
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hourglass_empty, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 20),
              Text(
                'Estás en ${s.grupo}, pero todavía sin equipo',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                s.tengoCedula
                    ? 'En cuanto tu capitán te fiche con tu cédula, aparecerás '
                        'en la plantilla. También puedes entrar con la clave '
                        'que te dé él.'
                    : 'Registra tu cédula para que tu capitán pueda ficharte, '
                        'o entra con la clave que te dé.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ClaveScreen(session: session, puedeVolver: true),
                  ),
                ),
                icon: const Icon(Icons.vpn_key),
                label: const Text('Tengo la clave de mi equipo'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
