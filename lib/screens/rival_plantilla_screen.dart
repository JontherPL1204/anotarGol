import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/session.dart';
import '../data/club_admin.dart';
import '../models/models.dart';
import '../widgets/estado_vacio.dart';
import '../widgets/formulario_jugador.dart';

/// Plantilla de un equipo rival.
///
/// Lo importante de esta pantalla es la honestidad: los jugadores
/// inventados se ven distintos y llevan la palabra "inventado" encima.
/// En cuanto alguien edita uno a mano, deja de estar marcado, porque ya
/// es un dato real.
class RivalPlantillaScreen extends StatefulWidget {
  const RivalPlantillaScreen({
    super.key,
    required this.rival,
    required this.admin,
    this.session,
  });

  final Rival rival;
  final ClubAdmin admin;
  final Session? session;

  @override
  State<RivalPlantillaScreen> createState() => _RivalPlantillaScreenState();
}

class _RivalPlantillaScreenState extends State<RivalPlantillaScreen> {
  late Future<List<RivalPlayer>> _carga =
      widget.admin.jugadoresRivales(widget.rival.id);

  List<RivalPlayer> _ultima = const [];

  bool get _puedeEditar =>
      (widget.session?.puedeEditarPlantilla ?? false) && widget.admin.disponible;

  Future<void> _recargar() async {
    final futuro = widget.admin.jugadoresRivales(widget.rival.id);
    setState(() => _carga = futuro);
    await futuro.catchError((_) => <RivalPlayer>[]);
  }

  void _avisar(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
    ));
  }

  List<int> _dorsalesOcupados({String? excepto}) => _ultima
      .where((j) => j.id != excepto && j.number != null)
      .map((j) => j.number!)
      .toList();

  Future<void> _generar() async {
    final hayReales = _ultima.any((j) => !j.isImaginary);

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Inventar la plantilla?'),
        content: Text(
          'Se arma un 11 con nombres ficticios para poder registrar el '
          'partido sin tener los datos reales del rival.\n\n'
          '${hayReales ? 'Los jugadores que cargaste a mano NO se tocan. ' : ''}'
          'Los inventados anteriores se reemplazan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1B5E20)),
            child: const Text('Inventar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await widget.admin.generarPlantillaImaginaria(widget.rival.id);
      _avisar('Plantilla inventada. Recuerda que esos nombres no son reales.');
      await _recargar();
    } catch (_) {
      _avisar('No se pudo generar. Revisa tus permisos.', error: true);
    }
  }

  Future<void> _agregar() async {
    final datos = await mostrarFormularioJugador(
      context,
      titulo: 'Jugador de ${widget.rival.name}',
      dorsalesOcupados: _dorsalesOcupados(),
    );
    if (datos == null) return;

    try {
      await widget.admin.agregarJugadorRival(
        rivalId: widget.rival.id,
        nombre: datos.nombre,
        dorsal: datos.dorsal,
        posicion: datos.posicion,
        detallePosicion: datos.detallePosicion,
      );
      _avisar('${datos.nombre} agregado.');
      await _recargar();
    } catch (_) {
      _avisar('No se pudo guardar.', error: true);
    }
  }

  Future<void> _editar(RivalPlayer jugador) async {
    final datos = await mostrarFormularioJugador(
      context,
      titulo: jugador.isImaginary ? 'Corregir con el dato real' : 'Editar jugador',
      nombre: jugador.fullName,
      dorsal: jugador.number,
      posicion: jugador.position,
      detallePosicion: jugador.positionDetail,
      dorsalesOcupados: _dorsalesOcupados(excepto: jugador.id),
    );
    if (datos == null) return;

    try {
      await widget.admin.actualizarJugadorRival(jugador.copyWith(
        fullName: datos.nombre,
        number: datos.dorsal,
        position: datos.posicion,
        positionDetail: datos.detallePosicion,
      ));
      _avisar(jugador.isImaginary
          ? 'Guardado. Ya no figura como inventado.'
          : 'Cambios guardados.');
      await _recargar();
    } catch (_) {
      _avisar('No se pudo guardar.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.rival.name,
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1B5E20),
        foregroundColor: Colors.white,
        actions: [
          if (_puedeEditar)
            IconButton(
              onPressed: _generar,
              icon: const Icon(Icons.auto_awesome),
              tooltip: 'Inventar plantilla',
            ),
        ],
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
      body: FutureBuilder<List<RivalPlayer>>(
        future: _carga,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return EstadoVacio(
              icono: Icons.cloud_off,
              titulo: 'No se pudo cargar la plantilla del rival',
              onReintentar: _recargar,
            );
          }

          final jugadores = snapshot.data ?? const <RivalPlayer>[];
          _ultima = jugadores;

          if (jugadores.isEmpty) {
            return EstadoVacio(
              icono: Icons.group_off_outlined,
              titulo: 'No hay jugadores cargados',
              mensaje: _puedeEditar
                  ? 'Agrégalos uno por uno, o usa la varita de arriba para '
                      'inventar un 11 y poder jugar igual.'
                  : 'El club todavía no cargó la plantilla de este rival.',
            );
          }

          final inventados = jugadores.where((j) => j.isImaginary).length;

          return RefreshIndicator(
            onRefresh: _recargar,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
              itemCount: jugadores.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return _AvisoInventados(
                    total: jugadores.length,
                    inventados: inventados,
                    editable: _puedeEditar,
                  );
                }
                final j = jugadores[i - 1];
                return _TarjetaRivalPlayer(
                  jugador: j,
                  editable: _puedeEditar,
                  onEditar: () => _editar(j),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Cartel que deja claro cuanto de lo que se ve es inventado.
class _AvisoInventados extends StatelessWidget {
  const _AvisoInventados({
    required this.total,
    required this.inventados,
    required this.editable,
  });

  final int total;
  final int inventados;
  final bool editable;

  @override
  Widget build(BuildContext context) {
    if (inventados == 0) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Row(
          children: [
            Icon(Icons.verified_outlined, size: 18, color: Colors.green.shade700),
            const SizedBox(width: 8),
            Text('$total jugadores, todos con datos reales',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.shade600),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_awesome, color: Colors.amber.shade800, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  inventados == total
                      ? 'Esta plantilla es inventada'
                      : '$inventados de $total jugadores son inventados',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  editable
                      ? 'Se generó por falta de información del rival. '
                          'Toca cualquiera para poner el dato real.'
                      : 'Se generó por falta de información del rival.',
                  style: TextStyle(fontSize: 12, color: Colors.brown.shade800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TarjetaRivalPlayer extends StatelessWidget {
  const _TarjetaRivalPlayer({
    required this.jugador,
    required this.editable,
    required this.onEditar,
  });

  final RivalPlayer jugador;
  final bool editable;
  final VoidCallback onEditar;

  Color get _color => switch (jugador.position) {
        PlayerPosition.gk => Colors.orange.shade700,
        PlayerPosition.df => Colors.blue.shade700,
        PlayerPosition.mf => const Color(0xFF1B5E20),
        PlayerPosition.fw => Colors.red.shade700,
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: jugador.isImaginary ? 0 : 2,
      color: jugador.isImaginary ? Colors.amber.shade50 : null,
      shape: jugador.isImaginary
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.amber.shade300),
            )
          : null,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        onTap: editable ? onEditar : null,
        leading: CircleAvatar(
          backgroundColor: jugador.isImaginary ? Colors.grey.shade400 : _color,
          foregroundColor: Colors.white,
          child: Text(jugador.shirtLabel,
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                jugador.fullName,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontStyle: jugador.isImaginary ? FontStyle.italic : null,
                ),
              ),
            ),
            if (jugador.isImaginary) ...[
              const SizedBox(width: 6),
              Icon(Icons.auto_awesome, size: 14, color: Colors.amber.shade800),
            ],
          ],
        ),
        subtitle: Text(
          jugador.isImaginary
              ? '${jugador.positionLabel} · inventado'
              : jugador.positionLabel,
          style: TextStyle(
            fontSize: 12,
            color: jugador.isImaginary ? Colors.brown.shade700 : null,
          ),
        ),
        trailing: Text(
          jugador.position.wire,
          style: TextStyle(
            color: jugador.isImaginary ? Colors.grey.shade600 : _color,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
