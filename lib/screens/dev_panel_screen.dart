import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/models.dart';
import '../repositories/repositories.dart';

/// El panel de desarrollo: todas las ligas y todos los equipos.
///
/// Antes de llegar aquí hay que canjear la clave de acceso o abrir el
/// panel. Las vistas están filtradas por `dev_panel_abierto()` en la
/// propia base, así que si el panel se cierra mientras la pantalla está
/// abierta, las listas se vacían solas.
class DevPanelScreen extends StatefulWidget {
  const DevPanelScreen({super.key, this.dev = const DevRepository()});

  final DevRepository dev;

  @override
  State<DevPanelScreen> createState() => _DevPanelScreenState();
}

class _DevPanelScreenState extends State<DevPanelScreen> {
  List<GrupoDev> _ligas = const [];
  List<EquipoDev> _equipos = const [];
  PanelDev _estado = const PanelDev();
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final estado = await widget.dev.estado();
      final ligas = await widget.dev.ligas();
      final equipos = await widget.dev.equipos();
      if (!mounted) return;
      setState(() {
        _estado = estado;
        _ligas = ligas;
        _equipos = equipos;
        _cargando = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _avisar(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
    ));
  }

  Future<void> _crearLiga() async {
    final nombre = await showDialog<String>(
      context: context,
      builder: (context) => const _DialogoTexto(
        titulo: 'Nueva liga',
        etiqueta: 'Nombre (opcional)',
        ayuda: 'Si lo dejas vacío se llamará "La Liga A", B, C…',
        obligatorio: false,
      ),
    );
    if (nombre == null) return;

    try {
      await widget.dev.crearLiga(nombre: nombre.isEmpty ? null : nombre);
      _avisar('Liga creada.');
      await _cargar();
    } catch (_) {
      _avisar('No se pudo crear la liga.', error: true);
    }
  }

  Future<void> _renombrar(GrupoDev liga) async {
    final nombre = await showDialog<String>(
      context: context,
      builder: (context) => _DialogoTexto(
        titulo: 'Renombrar liga',
        etiqueta: 'Nuevo nombre',
        inicial: liga.name,
      ),
    );
    if (nombre == null || nombre.isEmpty) return;

    try {
      await widget.dev.renombrarLiga(groupId: liga.id, nombre: nombre);
      _avisar('Liga renombrada.');
      await _cargar();
    } catch (_) {
      _avisar('No se pudo renombrar.', error: true);
    }
  }

  Future<void> _claveCapitan(GrupoDev liga) async {
    try {
      final codigo = await widget.dev.claveDeCapitan(groupId: liga.id);
      if (!mounted) return;
      await _mostrarCodigo(
        titulo: 'Clave de capitán',
        codigo: codigo,
        detalle: 'Dásela a un capitán de ${liga.name}. Con ella entra a la '
            'liga y puede fundar su equipo. Es de un solo uso.',
      );
    } catch (_) {
      _avisar('No se pudo generar la clave.', error: true);
    }
  }

  Future<void> _mostrarCodigo({
    required String titulo,
    required String codigo,
    required String detalle,
  }) =>
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(titulo),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(detalle, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 16),
              SelectableText(
                codigo,
                style: GoogleFonts.robotoMono(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 5,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: codigo));
                Navigator.pop(context);
                _avisar('Copiada.');
              },
              child: const Text('Copiar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Listo'),
            ),
          ],
        ),
      );

  Future<void> _borrarLiga(GrupoDev liga) async {
    // Se escribe el nombre a mano: borrar una liga se lleva por delante
    // sus equipos, jugadores, partidos e historial.
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => _DialogoBorrar(
        que: 'la liga ${liga.name}',
        arrastra: '${liga.equipos} equipos, ${liga.miembros} miembros y '
            '${liga.partidos} partidos',
        palabra: liga.name,
      ),
    );
    if (confirmado != true) return;

    try {
      await widget.dev.borrarLiga(liga.id);
      _avisar('${liga.name} borrada.');
      await _cargar();
    } catch (_) {
      _avisar('No se pudo borrar. ¿Sigue abierto el panel?', error: true);
    }
  }

  Future<void> _borrarEquipo(EquipoDev equipo) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => _DialogoBorrar(
        que: equipo.etiqueta,
        arrastra: '${equipo.jugadores} jugadores y su historial',
        palabra: equipo.nombre,
      ),
    );
    if (confirmado != true) return;

    try {
      await widget.dev.borrarEquipo(equipo.id);
      _avisar('Equipo borrado.');
      await _cargar();
    } catch (_) {
      _avisar('No se pudo borrar.', error: true);
    }
  }

  Future<void> _cerrar() async {
    await widget.dev.cerrarPanel();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final restante = _estado.restante;

    return Scaffold(
      appBar: AppBar(
        title: Text('Panel', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blueGrey.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _cerrar,
            icon: const Icon(Icons.lock),
            tooltip: 'Cerrar el panel',
          ),
        ],
        bottom: restante == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(26),
                child: Container(
                  width: double.infinity,
                  color: Colors.blueGrey.shade800,
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'Se cierra solo en ${restante.inMinutes + 1} min',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _crearLiga,
        backgroundColor: Colors.blueGrey.shade900,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nueva liga'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: _ligas.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 80),
                        Icon(Icons.emoji_events_outlined,
                            size: 56, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Center(
                          child: Text('Todavía no hay ligas',
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(height: 6),
                        Center(
                          child: Text(
                            'Crea la primera y reparte su clave de capitán.',
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey.shade600),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                      itemCount: _ligas.length,
                      itemBuilder: (context, i) {
                        final liga = _ligas[i];
                        final suyos = _equipos
                            .where((e) => e.groupId == liga.id)
                            .toList();
                        return _TarjetaLiga(
                          liga: liga,
                          equipos: suyos,
                          onClave: () => _claveCapitan(liga),
                          onRenombrar: () => _renombrar(liga),
                          onBorrar: () => _borrarLiga(liga),
                          onBorrarEquipo: _borrarEquipo,
                        );
                      },
                    ),
            ),
    );
  }
}

class _TarjetaLiga extends StatelessWidget {
  const _TarjetaLiga({
    required this.liga,
    required this.equipos,
    required this.onClave,
    required this.onRenombrar,
    required this.onBorrar,
    required this.onBorrarEquipo,
  });

  final GrupoDev liga;
  final List<EquipoDev> equipos;
  final VoidCallback onClave;
  final VoidCallback onRenombrar;
  final VoidCallback onBorrar;
  final void Function(EquipoDev) onBorrarEquipo;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blueGrey.shade700,
          foregroundColor: Colors.white,
          child: Text('${liga.equipos}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        title: Text(liga.name,
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${liga.equipos} equipos · ${liga.miembros} miembros · '
          '${liga.partidos} partidos',
          style: const TextStyle(fontSize: 12),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: onClave,
                  icon: const Icon(Icons.vpn_key, size: 18),
                  label: const Text('Clave de capitán'),
                ),
                TextButton.icon(
                  onPressed: onRenombrar,
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('Renombrar'),
                ),
                TextButton.icon(
                  onPressed: onBorrar,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Borrar'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
                ),
              ],
            ),
          ),
          if (equipos.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Sin equipos todavía',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
            )
          else
            for (final e in equipos)
              ListTile(
                dense: true,
                leading: Icon(
                  e.habilitado ? Icons.check_circle : Icons.hourglass_bottom,
                  size: 20,
                  color: e.habilitado ? Colors.green.shade600 : Colors.amber.shade700,
                ),
                title: Text(e.etiqueta, style: const TextStyle(fontSize: 14)),
                subtitle: Text(
                  e.habilitado
                      ? '${e.jugadores} jugadores · listo para jugar'
                      : 'Faltan ${e.faltan} con cédula'
                          '${e.tieneCapitan ? '' : ' · sin capitán'}',
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: IconButton(
                  onPressed: () => onBorrarEquipo(e),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: Colors.grey.shade600,
                ),
              ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _DialogoTexto extends StatefulWidget {
  const _DialogoTexto({
    required this.titulo,
    required this.etiqueta,
    this.inicial,
    this.ayuda,
    this.obligatorio = true,
  });

  final String titulo;
  final String etiqueta;
  final String? inicial;
  final String? ayuda;
  final bool obligatorio;

  @override
  State<_DialogoTexto> createState() => _DialogoTextoState();
}

class _DialogoTextoState extends State<_DialogoTexto> {
  late final _campo = TextEditingController(text: widget.inicial ?? '');
  String? _error;

  @override
  void dispose() {
    _campo.dispose();
    super.dispose();
  }

  void _aceptar() {
    final t = _campo.text.trim();
    if (widget.obligatorio && t.length < 2) {
      setState(() => _error = 'Escribe al menos 2 caracteres');
      return;
    }
    Navigator.pop(context, t);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: TextField(
        controller: _campo,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(
          labelText: widget.etiqueta,
          helperText: widget.ayuda,
          helperMaxLines: 2,
          errorText: _error,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _aceptar(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _aceptar, child: const Text('Aceptar')),
      ],
    );
  }
}

/// Confirmación para lo que no se puede deshacer.
///
/// Pide escribir el nombre: un borrado en cascada no debería estar a un
/// toque de distancia.
class _DialogoBorrar extends StatefulWidget {
  const _DialogoBorrar({
    required this.que,
    required this.arrastra,
    required this.palabra,
  });

  final String que;
  final String arrastra;
  final String palabra;

  @override
  State<_DialogoBorrar> createState() => _DialogoBorrarState();
}

class _DialogoBorrarState extends State<_DialogoBorrar> {
  final _campo = TextEditingController();
  bool _coincide = false;

  @override
  void initState() {
    super.initState();
    _campo.addListener(() {
      final ok = _campo.text.trim().toLowerCase() ==
          widget.palabra.trim().toLowerCase();
      if (ok != _coincide) setState(() => _coincide = ok);
    });
  }

  @override
  void dispose() {
    _campo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('¿Borrar ${widget.que}?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Se lleva por delante ${widget.arrastra}. No se puede deshacer.',
              style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 16),
          Text('Escribe "${widget.palabra}" para confirmar:',
              style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          TextField(
            controller: _campo,
            autofocus: true,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _coincide ? () => Navigator.pop(context, true) : null,
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          child: const Text('Borrar'),
        ),
      ],
    );
  }
}
