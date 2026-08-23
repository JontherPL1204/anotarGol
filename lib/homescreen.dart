import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/session.dart';
import 'data/club_admin.dart';
import 'data/club_data_source.dart';
import 'models/models.dart';
import 'plantilla.dart';
import 'screens/cuenta_screen.dart';
import 'screens/goleadores_screen.dart';
import 'screens/login_screen.dart';
import 'screens/rivales_screen.dart';
import 'widgets/marcador_card.dart';
import 'widgets/proximo_partido_card.dart';

/// Pantalla principal del club.
///
/// Ya no guarda datos: los pide a [ClubDataSource] y compone widgets. El
/// marcador vive en `widgets/marcador_card.dart` y el proximo partido en
/// `widgets/proximo_partido_card.dart`, para que este archivo no vuelva a
/// crecer sin control (era una de las debilidades del plan).
class Homescreen extends StatefulWidget {
  const Homescreen({super.key, this.dataSource, this.session, this.admin});

  /// Se inyecta en las pruebas. En la app se resuelve solo.
  final ClubDataSource? dataSource;

  /// Quien esta usando la app. `null` = modo invitado sin backend.
  final Session? session;

  /// Escrituras y rankings. Se inyecta en las pruebas.
  final ClubAdmin? admin;

  @override
  State<Homescreen> createState() => _HomescreenState();
}

class _HomescreenState extends State<Homescreen> {
  late ClubDataSource _fuente;
  late ClubAdmin _admin;

  bool _verProximoPartido = false;
  int? _totalJugadores;
  FootballMatch? _proximoPartido;

  @override
  void initState() {
    super.initState();
    _fuente = widget.dataSource ?? ClubDataSource.resolve();
    _admin = widget.admin ?? const ClubAdmin();
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

  void _abrirCuenta() {
    final sesion = widget.session;
    if (sesion == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => sesion.haySesion
            ? CuentaScreen(session: sesion)
            : LoginScreen(session: sesion),
      ),
    );
  }

  Future<void> _abrirPlantilla() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlantillaScreen(
          dataSource: _fuente,
          session: widget.session,
          admin: _admin,
        ),
      ),
    );
    // La plantilla pudo cambiar: refresca el contador de la tarjeta.
    await _cargar();
  }

  void _abrirRivales() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RivalesScreen(
          admin: _admin,
          session: widget.session,
        ),
      ),
    );
  }

  void _abrirGoleadores() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => GoleadoresScreen(admin: _admin)),
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
        actions: [
          if (widget.session != null)
            ListenableBuilder(
              listenable: widget.session!,
              builder: (context, _) => IconButton(
                onPressed: _abrirCuenta,
                tooltip: widget.session!.haySesion
                    ? 'Mi cuenta (${widget.session!.rolLegible})'
                    : 'Iniciar sesión',
                icon: Icon(widget.session!.haySesion
                    ? Icons.account_circle
                    : Icons.login),
              ),
            ),
          const Padding(
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

              MarcadorCard(dataSource: _fuente, session: widget.session),

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

              const SizedBox(height: 20),

              _AccesosDirectos(
                onGoleadores: _abrirGoleadores,
                onRivales: _abrirRivales,
                habilitado: _admin.disponible,
              ),
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

/// Accesos al ranking y a los equipos rivales.
class _AccesosDirectos extends StatelessWidget {
  const _AccesosDirectos({
    required this.onGoleadores,
    required this.onRivales,
    required this.habilitado,
  });

  final VoidCallback onGoleadores;
  final VoidCallback onRivales;

  /// Sin backend no hay ranking ni rivales que mostrar.
  final bool habilitado;

  @override
  Widget build(BuildContext context) {
    if (!habilitado) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          'Conecta el club para ver goleadores y equipos rivales.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: _Acceso(
            icono: Icons.emoji_events,
            titulo: 'Goleadores',
            detalle: 'Ranking e historial',
            color: const Color(0xFFB8860B),
            onTap: onGoleadores,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _Acceso(
            icono: Icons.shield_outlined,
            titulo: 'Rivales',
            detalle: 'Equipos y plantillas',
            color: Colors.blueGrey.shade700,
            onTap: onRivales,
          ),
        ),
      ],
    );
  }
}

class _Acceso extends StatelessWidget {
  const _Acceso({
    required this.icono,
    required this.titulo,
    required this.detalle,
    required this.color,
    required this.onTap,
  });

  final IconData icono;
  final String titulo;
  final String detalle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Column(
            children: [
              Icon(icono, color: color, size: 28),
              const SizedBox(height: 8),
              Text(titulo,
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 2),
              Text(detalle,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
            ],
          ),
        ),
      ),
    );
  }
}
