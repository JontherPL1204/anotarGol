import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/session.dart';
import '../models/models.dart';

/// Quien eres y que puedes hacer en este club.
///
/// Tambien es donde la primera persona registrada toma el club con
/// `claim_team`, que es lo que la convierte en `owner` y le habilita
/// escribir. Sin este paso, una cuenta nueva solo puede mirar.
class CuentaScreen extends StatelessWidget {
  const CuentaScreen({super.key, required this.session});

  final Session session;

  Future<void> _reclamar(BuildContext context) async {
    final error = await session.reclamarClub();
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? '¡Listo! Ahora eres el dueño del club.'),
        backgroundColor: error == null ? Colors.green.shade700 : Colors.red.shade700,
      ),
    );
  }

  Future<void> _salir(BuildContext context) async {
    await session.salir();
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Mi cuenta', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1B5E20),
        foregroundColor: Colors.white,
      ),
      body: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          if (!session.haySesion) {
            return const Center(child: Text('No hay sesión iniciada.'));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 34,
                        backgroundColor: const Color(0xFF1B5E20),
                        foregroundColor: Colors.white,
                        child: Text(
                          session.nombre.characters.first.toUpperCase(),
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        session.nombre,
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (session.usuario?.email != null)
                        Text(
                          session.usuario!.email!,
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                        ),
                      const SizedBox(height: 14),
                      Chip(
                        avatar: Icon(
                          session.puedeEditar ? Icons.verified_user : Icons.visibility,
                          size: 18,
                          color: session.puedeEditar ? Colors.green.shade800 : Colors.grey.shade700,
                        ),
                        label: Text(session.rolLegible),
                        backgroundColor: session.puedeEditar
                            ? Colors.green.shade50
                            : Colors.grey.shade200,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              _QuePuedesHacer(rol: session.rol),

              if (session.rol == null) ...[
                const SizedBox(height: 16),
                Card(
                  color: Colors.amber.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.flag_outlined, color: Colors.amber.shade800),
                            const SizedBox(width: 8),
                            Text(
                              'Todavía no perteneces al club',
                              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Si eres quien lo administra y el club aún no tiene dueño, '
                          'puedes tomarlo ahora. Si ya tiene dueño, pídele que te invite.',
                          style: TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: session.ocupado ? null : () => _reclamar(context),
                          icon: const Icon(Icons.workspace_premium),
                          label: const Text('Tomar el club'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF1B5E20),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 24),

              OutlinedButton.icon(
                onPressed: session.ocupado ? null : () => _salir(context),
                icon: const Icon(Icons.logout),
                label: const Text('Cerrar sesión'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  side: BorderSide(color: Colors.red.shade200),
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

/// Traduce el rol a permisos concretos, para que nadie tenga que
/// adivinar por que un boton esta apagado.
class _QuePuedesHacer extends StatelessWidget {
  const _QuePuedesHacer({required this.rol});

  final TeamRole? rol;

  @override
  Widget build(BuildContext context) {
    final permisos = <(String, bool)>[
      ('Ver plantilla, calendario y marcador', true),
      ('Registrar goles y tarjetas', rol?.canEdit ?? false),
      ('Editar jugadores y partidos', rol?.canEdit ?? false),
      ('Gestionar miembros del club', rol?.canAdmin ?? false),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Qué puedes hacer', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            for (final (texto, permitido) in permisos)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      permitido ? Icons.check_circle : Icons.remove_circle_outline,
                      size: 18,
                      color: permitido ? Colors.green.shade700 : Colors.grey.shade400,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        texto,
                        style: TextStyle(
                          fontSize: 13,
                          color: permitido ? Colors.black87 : Colors.grey.shade500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
