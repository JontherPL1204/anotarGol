import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/cedula.dart';
import '../core/session.dart';
import '../models/models.dart';
import '../repositories/repositories.dart';
import '../widgets/formulario_jugador.dart';

/// El armado de los 11 obligatorios, por cédula.
///
/// La cédula es lo que une la ficha con la persona: el capitán carga a
/// su gente antes de que se registren, y cada uno recibe su ficha al
/// crear la cuenta con esa misma cédula.
///
/// Los avisos de composición (dos porteros, posiciones repetidas) salen
/// solo aquí, mientras arma el equipo. Al confirmar se apagan: después,
/// un club con 20 fichados va a tener cuatro laterales derechos y está
/// bien.
class PlantillaInicialScreen extends StatefulWidget {
  const PlantillaInicialScreen({
    super.key,
    required this.session,
    required this.teamId,
    required this.nombreEquipo,
    this.capitan = const CapitanRepository(),
    this.jugadores = const PlayersRepository(),
  });

  final Session session;
  final String teamId;
  final String nombreEquipo;
  final CapitanRepository capitan;
  final PlayersRepository jugadores;

  @override
  State<PlantillaInicialScreen> createState() => _PlantillaInicialScreenState();
}

class _PlantillaInicialScreenState extends State<PlantillaInicialScreen> {
  List<Player> _plantilla = const [];
  EstadoPlantilla? _estado;
  List<AvisoPlantilla> _avisos = const [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final plantilla = await widget.jugadores.fetchByTeam(widget.teamId);
      final estado = await widget.capitan.estadoPlantilla(widget.teamId);
      final avisos = await widget.capitan.avisos(widget.teamId);
      if (!mounted) return;
      setState(() {
        _plantilla = plantilla;
        _estado = estado;
        _avisos = avisos;
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

  List<int> get _dorsalesOcupados =>
      _plantilla.where((j) => j.number != null).map((j) => j.number!).toList();

  Future<void> _fichar() async {
    final datos = await _pedirCedulaYDatos();
    if (datos == null) return;

    try {
      await widget.capitan.ficharJugador(
        teamId: widget.teamId,
        cedula: datos.$1,
        nombre: datos.$2.nombre,
        dorsal: datos.$2.dorsal,
        posicion: datos.$2.posicion,
        detallePosicion: datos.$2.detallePosicion,
      );
      _avisar('${datos.$2.nombre} fichado.');
      await _cargar();
    } catch (e) {
      final m = e.toString().toLowerCase();
      if (m.contains('ya juega en')) {
        _avisar('Esa cédula ya juega en otro equipo de esta liga.', error: true);
      } else if (m.contains('players_cedula_por_equipo') || m.contains('duplicate')) {
        _avisar('Esa cédula ya está en tu plantilla.', error: true);
      } else if (m.contains('players_cedula_chk')) {
        _avisar('Esa cédula no es válida.', error: true);
      } else {
        _avisar('No se pudo fichar. Revisa tu conexión.', error: true);
      }
    }
  }

  /// Primero la cédula, después el resto: es la identidad del jugador y
  /// lo que decide si ya está en otro equipo de la liga.
  Future<(String, DatosJugador)?> _pedirCedulaYDatos() async {
    final cedula = await showDialog<String>(
      context: context,
      builder: (context) => const _DialogoCedula(),
    );
    if (cedula == null || !mounted) return null;

    final datos = await mostrarFormularioJugador(
      context,
      titulo: 'Jugador ${Cedula.formatear(cedula)}',
      dorsalesOcupados: _dorsalesOcupados,
    );
    if (datos == null) return null;

    return (cedula, datos);
  }

  Future<void> _sacar(Player jugador) async {
    if (jugador.id.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Sacar a ${jugador.fullName}?'),
        content: const Text(
          'Sale de la plantilla. Si ya tenía goles, se quedan en el historial.',
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
    if (ok != true) return;

    try {
      await widget.jugadores.deactivate(jugador.id);
      _avisar('${jugador.fullName} salió de la plantilla.');
      await _cargar();
    } catch (_) {
      _avisar('No se pudo sacar.', error: true);
    }
  }

  Future<void> _confirmar() async {
    final avisos = _avisos.where((a) => !a.esBloqueo).toList();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Confirmar la plantilla?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tu equipo queda habilitado para retar y ser retado.\n',
            ),
            if (avisos.isNotEmpty) ...[
              const Text('Quedan estas observaciones:',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              for (final a in avisos)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• ${a.mensaje}',
                      style: const TextStyle(fontSize: 13)),
                ),
              const SizedBox(height: 8),
              const Text(
                'Son decisión tuya. Después de confirmar dejan de aparecer.',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Seguir armando'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1B5E20)),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await widget.capitan.confirmarPlantilla(widget.teamId);
      await widget.session.cargarSituacion();
      if (!mounted) return;
      _avisar('Plantilla confirmada. Tu equipo ya puede jugar.');
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (_) {
      _avisar('No se pudo confirmar.', error: true);
    }
  }

  Future<void> _compartirClave() async {
    try {
      final codigo = await widget.capitan.crearClaveDeEquipo(teamId: widget.teamId);
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Clave de tu equipo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Dásela a tus jugadores. Con ella entran a la liga y a tu '
                'equipo directamente.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              SelectableText(
                codigo,
                style: GoogleFonts.robotoMono(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 6,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: codigo));
                Navigator.pop(context);
                _avisar('Clave copiada.');
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
    } catch (_) {
      _avisar('No se pudo generar la clave.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = _estado;
    final habilitado = e?.habilitado ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.nombreEquipo,
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1B5E20),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _compartirClave,
            icon: const Icon(Icons.vpn_key),
            tooltip: 'Clave para mis jugadores',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _fichar,
        backgroundColor: const Color(0xFF1B5E20),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add),
        label: const Text('Fichar'),
      ),
      bottomNavigationBar: habilitado
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: _confirmar,
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Confirmar plantilla'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1B5E20),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            )
          : null,
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                children: [
                  _Progreso(estado: e),
                  const SizedBox(height: 16),
                  for (final a in _avisos) _Aviso(aviso: a),
                  if (_avisos.isNotEmpty) const SizedBox(height: 8),
                  if (_plantilla.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Column(
                        children: [
                          Icon(Icons.groups_outlined,
                              size: 56, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text('Todavía no hay nadie fichado',
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Text(
                            'Toca "Fichar" y empieza por la cédula de cada uno.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    )
                  else
                    for (final j in _plantilla)
                      _Fichado(jugador: j, onSacar: () => _sacar(j)),
                ],
              ),
            ),
    );
  }
}

class _Progreso extends StatelessWidget {
  const _Progreso({required this.estado});

  final EstadoPlantilla? estado;

  @override
  Widget build(BuildContext context) {
    final e = estado;
    if (e == null) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('${e.conCedula} de 11',
                    style: GoogleFonts.bebasNeue(
                        fontSize: 32, color: const Color(0xFF1B5E20))),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    e.habilitado
                        ? 'Ya puedes confirmar la plantilla'
                        : 'Faltan ${e.faltan} para poder jugar',
                    style: GoogleFonts.poppins(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: e.progreso,
                minHeight: 8,
                backgroundColor: Colors.grey.shade200,
                color: e.habilitado ? Colors.green.shade600 : Colors.amber.shade700,
              ),
            ),
            if (e.yaRegistrados > 0) ...[
              const SizedBox(height: 8),
              Text('${e.yaRegistrados} ya crearon su cuenta',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.aviso});

  final AvisoPlantilla aviso;

  @override
  Widget build(BuildContext context) {
    final bloqueo = aviso.esBloqueo;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bloqueo ? Colors.red.shade50 : Colors.amber.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: bloqueo ? Colors.red.shade200 : Colors.amber.shade300),
      ),
      child: Row(
        children: [
          Icon(bloqueo ? Icons.block : Icons.info_outline,
              size: 18,
              color: bloqueo ? Colors.red.shade700 : Colors.amber.shade800),
          const SizedBox(width: 10),
          Expanded(
            child: Text(aviso.mensaje,
                style: TextStyle(
                    fontSize: 13,
                    color: bloqueo ? Colors.red.shade900 : Colors.brown.shade800)),
          ),
        ],
      ),
    );
  }
}

class _Fichado extends StatelessWidget {
  const _Fichado({required this.jugador, required this.onSacar});

  final Player jugador;
  final VoidCallback onSacar;

  Color get _color => switch (jugador.position) {
        PlayerPosition.gk => Colors.orange.shade700,
        PlayerPosition.df => Colors.blue.shade700,
        PlayerPosition.mf => const Color(0xFF1B5E20),
        PlayerPosition.fw => Colors.red.shade700,
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _color,
          foregroundColor: Colors.white,
          child: Text(jugador.shirtLabel,
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        title: Text(jugador.fullName,
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        subtitle: Text(jugador.positionLabel, style: const TextStyle(fontSize: 12)),
        trailing: IconButton(
          onPressed: onSacar,
          icon: const Icon(Icons.person_remove_outlined, size: 20),
          color: Colors.grey.shade600,
          tooltip: 'Sacar',
        ),
      ),
    );
  }
}

/// La cédula va primero y sola: es la identidad, y de ella depende que
/// el jugador reciba su ficha al registrarse.
class _DialogoCedula extends StatefulWidget {
  const _DialogoCedula();

  @override
  State<_DialogoCedula> createState() => _DialogoCedulaState();
}

class _DialogoCedulaState extends State<_DialogoCedula> {
  final _formulario = GlobalKey<FormState>();
  final _cedula = TextEditingController();

  @override
  void dispose() {
    _cedula.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cédula del jugador'),
      content: Form(
        key: _formulario,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Con esta cédula el jugador recibe su ficha cuando cree su '
              'cuenta. No se puede cambiar después.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _cedula,
              autofocus: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: GoogleFonts.robotoMono(
                  fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 3),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              decoration: const InputDecoration(
                hintText: '1750959676',
                border: OutlineInputBorder(),
                counterText: '',
              ),
              validator: Cedula.error,
              onFieldSubmitted: (_) => _seguir(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _seguir,
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1B5E20)),
          child: const Text('Siguiente'),
        ),
      ],
    );
  }

  void _seguir() {
    if (!_formulario.currentState!.validate()) return;
    Navigator.pop(context, _cedula.text.trim());
  }
}
