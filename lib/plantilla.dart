import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'data/club_data_source.dart';
import 'models/models.dart';
import 'widgets/estado_vacio.dart';

/// Plantilla del club.
///
/// Antes tenia los 11 jugadores escritos dentro del widget. Ahora los
/// pide a [ClubDataSource]: si hay backend vienen de Postgres, y si no,
/// de los datos de ejemplo. La pantalla no sabe cual de los dos es.
class PlantillaScreen extends StatefulWidget {
  const PlantillaScreen({super.key, this.dataSource});

  /// Se inyecta en las pruebas. En la app se resuelve solo.
  final ClubDataSource? dataSource;

  @override
  State<PlantillaScreen> createState() => _PlantillaScreenState();
}

class _PlantillaScreenState extends State<PlantillaScreen> {
  late ClubDataSource _fuente;
  late Future<List<Player>> _carga;

  @override
  void initState() {
    super.initState();
    _fuente = widget.dataSource ?? ClubDataSource.resolve();
    _carga = _fuente.fetchPlayers();
  }

  Future<void> _recargar() async {
    final futuro = _fuente.fetchPlayers();
    setState(() => _carga = futuro);
    await futuro.catchError((_) => <Player>[]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Plantilla del Club',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1B5E20),
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<Player>>(
        future: _carga,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return EstadoVacio(
              icono: Icons.cloud_off,
              titulo: 'No se pudo cargar la plantilla',
              mensaje: 'Revisa tu conexión e inténtalo de nuevo.',
              onReintentar: _recargar,
            );
          }

          final jugadores = snapshot.data ?? const <Player>[];

          if (jugadores.isEmpty) {
            return const EstadoVacio(
              icono: Icons.groups_outlined,
              titulo: 'Todavía no hay jugadores',
              mensaje: 'Agrega el primer jugador para armar la plantilla.',
            );
          }

          return RefreshIndicator(
            onRefresh: _recargar,
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: jugadores.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) return _Encabezado(total: jugadores.length, fuente: _fuente);
                return _TarjetaJugador(jugador: jugadores[index - 1]);
              },
            ),
          );
        },
      ),
    );
  }
}

class _Encabezado extends StatelessWidget {
  const _Encabezado({required this.total, required this.fuente});

  final int total;
  final ClubDataSource fuente;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
      child: Row(
        children: [
          const Icon(Icons.groups, color: Color(0xFF1B5E20)),
          const SizedBox(width: 8),
          Text(
            '$total ${total == 1 ? 'jugador' : 'jugadores'}',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          if (!fuente.isRemote)
            const Chip(
              label: Text('Datos de ejemplo', style: TextStyle(fontSize: 11)),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }
}

class _TarjetaJugador extends StatelessWidget {
  const _TarjetaJugador({required this.jugador});

  final Player jugador;

  /// Un color por linea del campo, para leer la plantilla de un vistazo.
  Color get _color => switch (jugador.position) {
        PlayerPosition.gk => Colors.orange.shade700,
        PlayerPosition.df => Colors.blue.shade700,
        PlayerPosition.mf => const Color(0xFF1B5E20),
        PlayerPosition.fw => Colors.red.shade700,
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _color,
          foregroundColor: Colors.white,
          child: Text(
            jugador.shirtLabel,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(
          jugador.fullName,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(jugador.positionLabel),
        trailing: Text(
          jugador.position.wire,
          style: TextStyle(
            color: _color,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
