import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/session.dart';
import '../models/models.dart';
import 'clave_screen.dart';

/// A qué liga entra quien pertenece a varias.
///
/// Aparece al iniciar sesión y solo cuando hay más de una: preguntar con
/// una sola opción sería un trámite. Desde aquí también se entra a una
/// liga nueva con su clave.
class ElegirLigaScreen extends StatelessWidget {
  const ElegirLigaScreen({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('¿A qué liga entras?',
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
      body: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final grupos = session.grupos;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Perteneces a ${grupos.length} ligas. Cada una es un espacio '
                'aparte: lo que pasa en una no se ve en la otra.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 16),
              for (final g in grupos) _TarjetaLiga(grupo: g, session: session),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ClaveScreen(session: session, puedeVolver: true),
                  ),
                ),
                icon: const Icon(Icons.vpn_key),
                label: const Text('Entrar a otra liga con su clave'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TarjetaLiga extends StatelessWidget {
  const _TarjetaLiga({required this.grupo, required this.session});

  final Grupo grupo;
  final Session session;

  @override
  Widget build(BuildContext context) {
    final actual = session.grupoActual?.id == grupo.id;

    return Card(
      elevation: actual ? 3 : 1,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: actual
            ? const BorderSide(color: Color(0xFF1B5E20), width: 2)
            : BorderSide.none,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        onTap: () => session.elegirGrupo(grupo.id),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF1B5E20),
          foregroundColor: Colors.white,
          child: const Icon(Icons.emoji_events),
        ),
        title: Text(grupo.name,
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${grupo.resumenEquipos} · ${grupo.rol.label}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
