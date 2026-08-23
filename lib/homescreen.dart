import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'data/club_data_source.dart';
import 'models/models.dart';
import 'plantilla.dart';
import 'widgets/marcador_card.dart';
import 'widgets/proximo_partido_card.dart';

/// Pantalla principal del club.
///
/// Ya no guarda datos: los pide a [ClubDataSource] y compone widgets. El
/// marcador vive en `widgets/marcador_card.dart` y el proximo partido en
/// `widgets/proximo_partido_card.dart`, para que este archivo no vuelva a
/// crecer sin control (era una de las debilidades del plan).
class Homescreen extends StatefulWidget {
  const Homescreen({super.key, this.dataSource});

  /// Se inyecta en las pruebas. En la app se resuelve solo.
  final ClubDataSource? dataSource;

  @override
  State<Homescreen> createState() => _HomescreenState();
}

class _HomescreenState extends State<Homescreen> {
  late ClubDataSource _fuente;

  bool _verProximoPartido = false;
  int? _totalJugadores;
  FootballMatch? _proximoPartido;

  @override
  void initState() {
    super.initState();
    _fuente = widget.dataSource ?? ClubDataSource.resolve();
    _cargar();
  }

  Future<void> _cargar() async {
    // Las dos cargas son independientes: si una falla, la otra igual se
    // muestra. La pantalla nunca se queda en blanco por un error de red.
    try {
      final jugadores = await _fuente.fetchPlayers();
      if (mounted) setState(() => _totalJugadores = jugadores.length);
    } catch (_) {
      if (mounted) setState(() => _totalJugadores = 0);
    }

    try {
      final partido = await _fuente.fetchNextMatch();
      if (mounted) setState(() => _proximoPartido = partido);
    } catch (_) {
      // Se queda en null y la caja dice que no hay partidos.
    }
  }

  void _toggleInfo() {
    setState(() => _verProximoPartido = !_verProximoPartido);
  }

  void _abrirPlantilla() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlantillaScreen(dataSource: _fuente),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B5E20),
        foregroundColor: Colors.white,
        centerTitle: true,
        title: Text(
          'Pasión Futbolera FC',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16.0),
            child: Icon(Icons.emoji_events, color: Color(0xFFFFD700)),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              const _BannerBienvenida(),

              const SizedBox(height: 20),

              _TarjetaEquipo(
                totalJugadores: _totalJugadores,
                onVerPlantilla: _abrirPlantilla,
              ),

              const SizedBox(height: 25),

              MarcadorCard(dataSource: _fuente),

              const SizedBox(height: 15),

              OutlinedButton.icon(
                onPressed: _toggleInfo,
                icon: Icon(_verProximoPartido
                    ? Icons.visibility_off
                    : Icons.visibility),
                label: Text(_verProximoPartido
                    ? 'Ocultar Calendario'
                    : 'Ver Próximo Partido'),
              ),

              if (_verProximoPartido)
                ProximoPartidoCard(partido: _proximoPartido),
            ],
          ),
        ),
      ),
    );
  }
}

class _BannerBienvenida extends StatelessWidget {
  const _BannerBienvenida();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Container(
        padding: const EdgeInsets.all(20),
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          color: const Color(0xFF1B5E20),
        ),
        child: Column(
          children: [
            const Icon(Icons.sports_soccer, size: 60, color: Colors.white),
            const SizedBox(height: 12),
            Text(
              '¡Bienvenidos al Club!',
              style: GoogleFonts.montserrat(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Seguimiento en vivo del partido',
              style: GoogleFonts.roboto(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _TarjetaEquipo extends StatelessWidget {
  const _TarjetaEquipo({
    required this.totalJugadores,
    required this.onVerPlantilla,
  });

  /// `null` mientras carga.
  final int? totalJugadores;
  final VoidCallback onVerPlantilla;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            const Column(
              children: [
                Icon(Icons.shield, color: Colors.green),
                SizedBox(height: 4),
                Text('Equipo Local',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            Container(height: 40, width: 1, color: Colors.grey[300]),

            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onVerPlantilla,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8.0,
                  vertical: 4.0,
                ),
                child: Column(
                  children: [
                    const Icon(Icons.groups, color: Colors.blue),
                    const SizedBox(height: 4),
                    Text(
                      totalJugadores == null
                          ? 'Plantilla'
                          : 'Plantilla: $totalJugadores',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    const Text(
                      '(Toca para ver)',
                      style: TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
