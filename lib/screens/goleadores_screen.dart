import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/club_admin.dart';
import '../models/models.dart';
import '../widgets/estado_vacio.dart';
import '../widgets/proximo_partido_card.dart' show formatearFecha;

/// Ranking de goleadores e historial de goles.
///
/// El ranking responde "quien mete goles"; el historial, "que paso en
/// cada partido". Los goleadores rivales aparecen tambien, marcados si
/// son jugadores inventados.
class GoleadoresScreen extends StatefulWidget {
  const GoleadoresScreen({super.key, required this.admin});

  final ClubAdmin admin;

  @override
  State<GoleadoresScreen> createState() => _GoleadoresScreenState();
}

class _GoleadoresScreenState extends State<GoleadoresScreen> {
  late Future<List<Goleador>> _ranking = widget.admin.goleadores();
  late Future<List<GolHistorial>> _historial = widget.admin.historialDeGoles();

  Future<void> _recargar() async {
    final r = widget.admin.goleadores();
    final h = widget.admin.historialDeGoles();
    setState(() {
      _ranking = r;
      _historial = h;
    });
    await Future.wait([
      r.catchError((_) => <Goleador>[]),
      h.catchError((_) => <GolHistorial>[]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Goleadores',
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF1B5E20),
          foregroundColor: Colors.white,
          bottom: const TabBar(
            indicatorColor: Color(0xFFFFD700),
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Ranking', icon: Icon(Icons.emoji_events)),
              Tab(text: 'Historial', icon: Icon(Icons.history)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _Ranking(carga: _ranking, onRecargar: _recargar),
            _Historial(carga: _historial, onRecargar: _recargar),
          ],
        ),
      ),
    );
  }
}

class _Ranking extends StatelessWidget {
  const _Ranking({required this.carga, required this.onRecargar});

  final Future<List<Goleador>> carga;
  final Future<void> Function() onRecargar;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Goleador>>(
      future: carga,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return EstadoVacio(
            icono: Icons.cloud_off,
            titulo: 'No se pudo cargar el ranking',
            mensaje: 'Necesitas conexión con el club para verlo.',
            onReintentar: onRecargar,
          );
        }

        final todos = snapshot.data ?? const <Goleador>[];
        if (todos.isEmpty) {
          return const EstadoVacio(
            icono: Icons.emoji_events_outlined,
            titulo: 'Todavía no hay goles',
            mensaje: 'En cuanto se registre el primero, aparecerá el ranking.',
          );
        }

        final nuestros = todos.where((g) => g.esDelClub).toList();
        final rivales = todos.where((g) => !g.esDelClub).toList();

        return RefreshIndicator(
          onRefresh: onRecargar,
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (nuestros.isNotEmpty) ...[
                _TituloSeccion(
                  icono: Icons.shield,
                  texto: 'Nuestro club',
                  color: const Color(0xFF1B5E20),
                ),
                for (final (i, g) in nuestros.indexed)
                  _FilaGoleador(goleador: g, puesto: i + 1),
              ],
              if (rivales.isNotEmpty) ...[
                const SizedBox(height: 20),
                _TituloSeccion(
                  icono: Icons.shield_outlined,
                  texto: 'Rivales',
                  color: Colors.blueGrey.shade700,
                ),
                for (final (i, g) in rivales.indexed)
                  _FilaGoleador(goleador: g, puesto: i + 1),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _TituloSeccion extends StatelessWidget {
  const _TituloSeccion({
    required this.icono,
    required this.texto,
    required this.color,
  });

  final IconData icono;
  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Row(
        children: [
          Icon(icono, size: 18, color: color),
          const SizedBox(width: 8),
          Text(texto,
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

class _FilaGoleador extends StatelessWidget {
  const _FilaGoleador({required this.goleador, required this.puesto});

  final Goleador goleador;
  final int puesto;

  /// Oro, plata y bronce para el podio; gris para el resto.
  Color get _colorPuesto => switch (puesto) {
        1 => const Color(0xFFFFC107),
        2 => const Color(0xFF9E9E9E),
        3 => const Color(0xFFA1662F),
        _ => Colors.grey.shade300,
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: puesto <= 3 ? 3 : 1,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: _colorPuesto, shape: BoxShape.circle),
          child: Text(
            '$puesto',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: puesto <= 3 ? Colors.white : Colors.black54,
            ),
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                goleador.nombre,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontStyle: goleador.esImaginario ? FontStyle.italic : null,
                ),
              ),
            ),
            if (goleador.esImaginario) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: 'Jugador inventado por falta de datos del rival',
                child: Icon(Icons.auto_awesome,
                    size: 14, color: Colors.amber.shade800),
              ),
            ],
          ],
        ),
        subtitle: Text(
          [
            if (goleador.dorsal != null) 'Dorsal ${goleador.dorsalLabel}',
            goleador.position.label,
            if (goleador.club != null) goleador.club!,
          ].join(' · '),
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${goleador.goles}',
              style: GoogleFonts.bebasNeue(
                  fontSize: 28, color: const Color(0xFF1B5E20)),
            ),
            Text(goleador.goles == 1 ? 'gol' : 'goles',
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

class _Historial extends StatelessWidget {
  const _Historial({required this.carga, required this.onRecargar});

  final Future<List<GolHistorial>> carga;
  final Future<void> Function() onRecargar;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<GolHistorial>>(
      future: carga,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return EstadoVacio(
            icono: Icons.cloud_off,
            titulo: 'No se pudo cargar el historial',
            onReintentar: onRecargar,
          );
        }

        final goles = snapshot.data ?? const <GolHistorial>[];
        if (goles.isEmpty) {
          return const EstadoVacio(
            icono: Icons.history,
            titulo: 'Sin goles registrados',
            mensaje: 'Cada gol que anotes quedará aquí, con minuto y autor.',
          );
        }

        return RefreshIndicator(
          onRefresh: onRecargar,
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: goles.length,
            itemBuilder: (context, i) {
              final g = goles[i];
              final nuevoPartido =
                  i == 0 || goles[i - 1].matchId != g.matchId;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (nuevoPartido)
                    Padding(
                      padding: EdgeInsets.only(top: i == 0 ? 0 : 16, bottom: 6, left: 4),
                      child: Text(
                        'vs ${g.rival} · ${formatearFecha(g.fecha)}',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    child: ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: g.esNuestro
                            ? const Color(0xFF1B5E20)
                            : Colors.blueGrey.shade400,
                        foregroundColor: Colors.white,
                        child: Text(
                          g.minutoLabel.isEmpty ? '⚽' : g.minutoLabel,
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              g.goleador,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontStyle:
                                    g.esImaginario ? FontStyle.italic : null,
                              ),
                            ),
                          ),
                          if (g.esImaginario) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.auto_awesome,
                                size: 13, color: Colors.amber.shade800),
                          ],
                          if (g.esAutogol) ...[
                            const SizedBox(width: 6),
                            Text('(en propia)',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.red.shade700)),
                          ],
                        ],
                      ),
                      subtitle: g.asistencia != null
                          ? Text('Asistencia: ${g.asistencia}',
                              style: const TextStyle(fontSize: 11))
                          : null,
                      trailing: Text(
                        g.esNuestro ? 'Nuestro' : 'Rival',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: g.esNuestro
                              ? const Color(0xFF1B5E20)
                              : Colors.blueGrey,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
