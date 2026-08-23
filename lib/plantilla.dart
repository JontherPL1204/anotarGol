import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/session.dart';
import 'data/club_admin.dart';
import 'data/club_data_source.dart';
import 'models/models.dart';
import 'widgets/estado_vacio.dart';
import 'widgets/formulario_jugador.dart';

/// Plantilla del club, editable por cualquier integrante.
///
/// El permiso lo decide [Session.puedeEditarPlantilla], que espeja la
/// funcion `can_edit_squad` de la base: dueño, administrador, cuerpo
/// tecnico y jugadores pueden editar; el hincha y el anonimo solo miran.
/// Si la interfaz se equivocara, RLS lo frena igual del lado del servidor.
class PlantillaScreen extends StatefulWidget {
  const PlantillaScreen({
    super.key,
    this.dataSource,
    this.session,
    this.admin,
  });

  final ClubDataSource? dataSource;
  final Session? session;
  final ClubAdmin? admin;

  @override
  State<PlantillaScreen> createState() => _PlantillaScreenState();
}

class _PlantillaScreenState extends State<PlantillaScreen> {
  late ClubDataSource _fuente;
  late ClubAdmin _admin;
  late Future<List<Player>> _carga;

  List<Player> _ultimaLista = const [];

  @override
  void initState() {
    super.initState();
    _fuente = widget.dataSource ?? ClubDataSource.resolve();
    _admin = widget.admin ?? const ClubAdmin();
    _carga = _fuente.fetchPlayers();
  }

  bool get _puedeEditar =>
      (widget.session?.puedeEditarPlantilla ?? false) && _admin.disponible;

  Future<void> _recargar() async {
    final futuro = _fuente.fetchPlayers();
    setState(() => _carga = futuro);
    await futuro.catchError((_) => <Player>[]);
  }

  void _avisar(String mensaje, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(mensaje),
      backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
    ));
  }

  List<int> _dorsalesOcupados({String? exceptoJugador}) => _ultimaLista
      .where((j) => j.id != exceptoJugador && j.number != null)
      .map((j) => j.number!)
      .toList();

  Future<void> _agregar() async {
    final datos = await mostrarFormularioJugador(
      context,
      titulo: 'Nuevo jugador',
      dorsalesOcupados: _dorsalesOcupados(),
    );
    if (datos == null) return;

    try {
      await _admin.crearJugador(
        nombre: datos.nombre,
        dorsal: datos.dorsal,
        posicion: datos.posicion,
        detallePosicion: datos.detallePosicion,
      );
      _avisar('${datos.nombre} se sumó a la plantilla.');
      await _recargar();
    } catch (_) {
      _avisar('No se pudo guardar. Revisa tu conexión o tus permisos.', error: true);
    }
  }

  Future<void> _editar(Player jugador) async {
    final datos = await mostrarFormularioJugador(
      context,
      titulo: 'Editar jugador',
      nombre: jugador.fullName,
      dorsal: jugador.number,
      posicion: jugador.position,
      detallePosicion: jugador.positionDetail,
      dorsalesOcupados: _dorsalesOcupados(exceptoJugador: jugador.id),
    );
    if (datos == null) return;

    try {
      await _admin.actualizarJugador(jugador.copyWith(
        fullName: datos.nombre,
        number: datos.dorsal,
        position: datos.posicion,
        positionDetail: datos.detallePosicion,
      ));
      _avisar('Cambios guardados.');
      await _recargar();
    } catch (_) {
      _avisar('No se pudo guardar. Revisa tu conexión o tus permisos.', error: true);
    }
  }

  Future<void> _darDeBaja(Player jugador) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Sacar a ${jugador.fullName}?'),
        content: const Text(
          'Sale de la plantilla activa, pero sus goles se conservan en el '
          'historial y en el ranking.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sacar'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;

    try {
      await _admin.darDeBaja(jugador.id);
      _avisar('${jugador.fullName} salió de la plantilla.');
      await _recargar();
    } catch (_) {
      _avisar('No se pudo quitar. Revisa tus permisos.', error: true);
    }
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
      floatingActionButton: _puedeEditar
          ? FloatingActionButton.extended(
              onPressed: _agregar,
              backgroundColor: const Color(0xFF1B5E20),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.person_add),
              label: const Text('Agregar'),
            )
          : null,
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
          _ultimaLista = jugadores;

          if (jugadores.isEmpty) {
            return EstadoVacio(
              icono: Icons.groups_outlined,
              titulo: 'Todavía no hay jugadores',
              mensaje: _puedeEditar
                  ? 'Toca "Agregar" para sumar al primero.'
                  : 'Cuando el club cargue su plantilla, aparecerá aquí.',
            );
          }

          return RefreshIndicator(
            onRefresh: _recargar,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
              itemCount: jugadores.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _Encabezado(
                    total: jugadores.length,
                    fuente: _fuente,
                    editable: _puedeEditar,
                  );
                }
                final jugador = jugadores[index - 1];
                return _TarjetaJugador(
                  jugador: jugador,
                  editable: _puedeEditar,
                  onEditar: () => _editar(jugador),
                  onQuitar: () => _darDeBaja(jugador),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _Encabezado extends StatelessWidget {
  const _Encabezado({
    required this.total,
    required this.fuente,
    required this.editable,
  });

  final int total;
  final ClubDataSource fuente;
  final bool editable;

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
            )
          else if (editable)
            Text(
              'Toca para editar',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
        ],
      ),
    );
  }
}

class _TarjetaJugador extends StatelessWidget {
  const _TarjetaJugador({
    required this.jugador,
    required this.editable,
    required this.onEditar,
    required this.onQuitar,
  });

  final Player jugador;
  final bool editable;
  final VoidCallback onEditar;
  final VoidCallback onQuitar;

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
        onTap: editable ? onEditar : null,
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
        trailing: editable
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    jugador.position.wire,
                    style: TextStyle(
                      color: _color,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  IconButton(
                    onPressed: onQuitar,
                    icon: const Icon(Icons.person_remove_outlined, size: 20),
                    tooltip: 'Sacar de la plantilla',
                    color: Colors.grey.shade600,
                  ),
                ],
              )
            : Text(
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
