import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/models.dart';
import '../repositories/repositories.dart';

const _verde = Color(0xFF1B5E20);

/// La plantilla de un equipo de la liga.
///
/// Solo se ve si hay partido concretado con él: la base lo decide en
/// `puedo_ver_plantilla()`, así que aquí no se replica la regla. Lo que
/// sí se hace es explicar el vacío, porque una lista sin jugadores y una
/// plantilla que todavía no se puede mirar son cosas distintas.
class EquipoLigaScreen extends StatefulWidget {
  const EquipoLigaScreen({
    super.key,
    required this.equipo,
    this.jugadores = const PlayersRepository(),
  });

  final EquipoDelGrupo equipo;
  final PlayersRepository jugadores;

  @override
  State<EquipoLigaScreen> createState() => _EquipoLigaScreenState();
}

class _EquipoLigaScreenState extends State<EquipoLigaScreen> {
  late Future<List<Player>> _carga =
      widget.jugadores.fetchByTeam(widget.equipo.id);

  @override
  Widget build(BuildContext context) {
    final e = widget.equipo;

    return Scaffold(
      appBar: AppBar(
        title: Text(e.name,
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        backgroundColor: _verde,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<Player>>(
        future: _carga,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final jugadores = snap.data ?? const <Player>[];

          if (jugadores.isEmpty) {
            // El equipo tiene gente cargada pero no llega ninguna fila:
            // la base la está tapando porque no hay partido acordado.
            final tapada = e.jugadores > 0;

            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(tapada ? Icons.lock_outline : Icons.group_off,
                        size: 56, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    Text(
                      tapada
                          ? 'Su plantilla todavía no se ve'
                          : 'Este equipo aún no carga jugadores',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tapada
                          ? 'Los jugadores del rival se ven cuando el partido '
                              'queda concretado. Rétalos y, si aceptan, '
                              'aparecen aquí.'
                          : 'Su capitán todavía no cargó la plantilla. '
                              'Sin los 11 con cédula no puede jugar.',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 13, color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              final f = widget.jugadores.fetchByTeam(e.id);
              setState(() => _carga = f);
              await f.catchError((_) => <Player>[]);
            },
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: jugadores.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final j = jugadores[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _verde,
                    foregroundColor: Colors.white,
                    child: Text(j.number?.toString() ?? '-',
                        style:
                            const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  title: Text(j.fullName,
                      style:
                          GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                  subtitle: Text(j.positionLabel),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
