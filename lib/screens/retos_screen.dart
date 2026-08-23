import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/session.dart';
import '../models/models.dart';
import '../repositories/repositories.dart';
import '../widgets/estado_vacio.dart';

const _verde = Color(0xFF1B5E20);

/// Retos entre capitanes: mandar uno y responder los que llegan.
///
/// Las dos cosas viven en la misma pantalla a propósito. Retar y ser
/// retado es la misma conversación mirada desde los dos lados, y
/// separarlas obligaría al capitán a acordarse de en qué pestaña estaba
/// lo que le importa.
///
/// Responder solo puede el equipo retado, y solo el capitán. La base lo
/// comprueba; aquí se ocultan los botones para no ofrecer lo imposible.
class RetosScreen extends StatefulWidget {
  const RetosScreen({
    super.key,
    required this.session,
    required this.teamId,
    required this.groupId,
    this.retos = const ChallengesRepository(),
  });

  final Session session;
  final String teamId;
  final String groupId;
  final ChallengesRepository retos;

  @override
  State<RetosScreen> createState() => _RetosScreenState();
}

class _RetosScreenState extends State<RetosScreen> {
  late Future<List<Reto>> _carga = widget.retos.misRetos(widget.teamId);
  bool _ocupado = false;

  Future<void> _recargar() async {
    final f = widget.retos.misRetos(widget.teamId);
    setState(() => _carga = f);
    await f.catchError((_) => <Reto>[]);
  }

  void _avisar(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m),
        backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
      ),
    );
  }

  /// Traduce los errores de la base a algo que un capitán entienda.
  String _enCristiano(Object e) {
    final m = e.toString().toLowerCase();
    if (m.contains('mismo grupo')) {
      return 'Solo puedes retar a equipos de tu liga.';
    }
    if (m.contains('once') || m.contains('11')) {
      return 'Uno de los dos equipos todavía no tiene los 11 con cédula.';
    }
    if (m.contains('conflicto') || m.contains('choca')) {
      return 'Ese horario choca con un partido ya acordado.';
    }
    if (m.contains('capitán') || m.contains('capitan') || m.contains('42501')) {
      return 'Esto es cosa de capitanes.';
    }
    if (m.contains('ya fue respondido')) {
      return 'Ese reto ya fue respondido.';
    }
    return 'No se pudo completar. Inténtalo de nuevo.';
  }

  Future<void> _retar() async {
    final equipos = await widget.retos.equiposParaRetar(widget.groupId);
    if (!mounted) return;

    if (equipos.isEmpty) {
      _avisar('Tu liga todavía no tiene otro equipo.');
      return;
    }

    final datos = await showModalBottomSheet<_Propuesta>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _FormularioReto(equipos: equipos),
      ),
    );
    if (datos == null || !mounted) return;

    setState(() => _ocupado = true);
    try {
      await widget.retos.retar(
        miEquipoId: widget.teamId,
        rivalId: datos.rivalId,
        cuando: datos.cuando,
        lugar: datos.lugar,
        minutos: datos.minutos,
        cambios: datos.cambios,
        mensaje: datos.mensaje,
      );
      _avisar('Reto enviado a ${datos.rivalNombre}.');
      await _recargar();
    } catch (e) {
      _avisar(_enCristiano(e), error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _responder(Reto reto, bool aceptar) async {
    final cuando = _fecha(reto.cuando);

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(aceptar ? '¿Aceptar el reto?' : '¿Rechazar el reto?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              aceptar
                  ? 'Queda acordado el partido contra ${reto.otroEquipo} '
                        'el $cuando, y aparece en el cronograma.'
                  : 'Se le avisa a ${reto.otroEquipo} que no juegas.',
            ),
            if (aceptar && reto.chocaConTuAgenda) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber,
                      color: Colors.orange.shade800,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Ese horario choca con otro partido tuyo.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: aceptar ? _verde : Colors.red.shade700,
            ),
            child: Text(aceptar ? 'Sí, acepto' : 'Sí, rechazo'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _ocupado = true);
    try {
      await widget.retos.responder(retoId: reto.id, aceptar: aceptar);
      _avisar(
        aceptar
            ? 'Partido acordado con ${reto.otroEquipo}. Ya está en el cronograma.'
            : 'Reto rechazado.',
      );
      await _recargar();
    } catch (e) {
      _avisar(_enCristiano(e), error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final soyCapitan = widget.session.situacion.soyCapitan;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Retos',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        backgroundColor: _verde,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _ocupado ? null : _recargar,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      floatingActionButton: soyCapitan
          ? FloatingActionButton.extended(
              onPressed: _ocupado ? null : _retar,
              backgroundColor: _verde,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.sports_soccer),
              label: const Text('Retar a un equipo'),
            )
          : null,
      body: FutureBuilder<List<Reto>>(
        future: _carga,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return const EstadoVacio(
              icono: Icons.cloud_off,
              titulo: 'No se pudieron cargar los retos',
              mensaje: 'Revisa tu conexión y vuelve a intentarlo.',
            );
          }

          final retos = snap.data ?? const <Reto>[];
          if (retos.isEmpty) {
            return EstadoVacio(
              icono: Icons.sports_soccer,
              titulo: 'Todavía no hay retos',
              mensaje: soyCapitan
                  ? 'Reta a otro equipo de tu liga para acordar un partido.'
                  : 'Cuando tu capitán acuerde un partido, aparecerá aquí.',
            );
          }

          return RefreshIndicator(
            onRefresh: _recargar,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: retos.length,
              itemBuilder: (context, i) => _TarjetaReto(
                reto: retos[i],
                puedeResponder: soyCapitan && retos[i].puedoResponder,
                ocupado: _ocupado,
                onAceptar: () => _responder(retos[i], true),
                onRechazar: () => _responder(retos[i], false),
              ),
            ),
          );
        },
      ),
    );
  }
}

String _fecha(DateTime d) {
  const meses = [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '${d.day} ${meses[d.month - 1]} · $hh:$mm';
}

class _TarjetaReto extends StatelessWidget {
  const _TarjetaReto({
    required this.reto,
    required this.puedeResponder,
    required this.ocupado,
    required this.onAceptar,
    required this.onRechazar,
  });

  final Reto reto;
  final bool puedeResponder;
  final bool ocupado;
  final VoidCallback onAceptar;
  final VoidCallback onRechazar;

  Color get _colorEstado => switch (reto.estado) {
    'pending' => Colors.orange.shade700,
    'accepted' || 'played' => _verde,
    'rejected' || 'cancelled' || 'expired' => Colors.grey.shade600,
    _ => Colors.grey.shade600,
  };

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: reto.pendiente ? Colors.orange.shade200 : Colors.grey.shade300,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  reto.soyRetador ? Icons.call_made : Icons.call_received,
                  size: 18,
                  color: _colorEstado,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    reto.soyRetador
                        ? 'Retaste a ${reto.otroEquipo}'
                        : '${reto.otroEquipo} te retó',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              reto.estadoLegible,
              style: TextStyle(
                color: _colorEstado,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),

            _Dato(icono: Icons.event, texto: _fecha(reto.cuando)),
            if (reto.lugar != null && reto.lugar!.isNotEmpty)
              _Dato(icono: Icons.place, texto: reto.lugar!),
            _Dato(
              icono: Icons.timer,
              texto: '${reto.minutos} minutos · ${reto.cambios} cambios',
            ),
            if (reto.mensaje != null && reto.mensaje!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '"${reto.mensaje}"',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: Colors.grey.shade700,
                  fontSize: 13,
                ),
              ),
            ],

            if (reto.chocaConTuAgenda && reto.pendiente) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber,
                      size: 18,
                      color: Colors.orange.shade800,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Choca con otro partido tuyo.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (puedeResponder) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: ocupado ? null : onRechazar,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade200),
                      ),
                      child: const Text('Rechazar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: ocupado ? null : onAceptar,
                      style: FilledButton.styleFrom(backgroundColor: _verde),
                      child: const Text('Aceptar'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        Icon(icono, size: 15, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Text(
          texto,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
        ),
      ],
    ),
  );
}

/// Lo que el capitán propone al retar.
class _Propuesta {
  const _Propuesta({
    required this.rivalId,
    required this.rivalNombre,
    required this.cuando,
    this.lugar,
    this.minutos = 90,
    this.cambios = 5,
    this.mensaje,
  });

  final String rivalId;
  final String rivalNombre;
  final DateTime cuando;
  final String? lugar;
  final int minutos;
  final int cambios;
  final String? mensaje;
}

class _FormularioReto extends StatefulWidget {
  const _FormularioReto({required this.equipos});

  final List<EquipoDelGrupo> equipos;

  @override
  State<_FormularioReto> createState() => _FormularioRetoState();
}

class _FormularioRetoState extends State<_FormularioReto> {
  // Arranca en el primero que de verdad se puede retar; si ninguno se
  // puede, en el primero a secas, para que el motivo quede a la vista.
  late EquipoDelGrupo _rival = widget.equipos.firstWhere(
    (e) => e.sePuedeRetar,
    orElse: () => widget.equipos.first,
  );
  DateTime? _cuando;
  final _lugar = TextEditingController();
  final _mensaje = TextEditingController();
  int _minutos = 90;
  int _cambios = 5;

  @override
  void dispose() {
    _lugar.dispose();
    _mensaje.dispose();
    super.dispose();
  }

  Future<void> _elegirCuando() async {
    final ahora = DateTime.now();
    final dia = await showDatePicker(
      context: context,
      initialDate: ahora.add(const Duration(days: 1)),
      firstDate: ahora,
      lastDate: ahora.add(const Duration(days: 365)),
    );
    if (dia == null || !mounted) return;

    final hora = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 16, minute: 0),
    );
    if (hora == null || !mounted) return;

    setState(
      () => _cuando = DateTime(
        dia.year,
        dia.month,
        dia.day,
        hora.hour,
        hora.minute,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Retar a un equipo',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'El otro capitán decide si acepta. Si acepta, el partido queda '
            'acordado y entra al cronograma.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 20),

          DropdownButtonFormField<EquipoDelGrupo>(
            initialValue: _rival,
            decoration: const InputDecoration(
              labelText: 'Equipo',
              prefixIcon: Icon(Icons.shield),
              border: OutlineInputBorder(),
            ),
            items: [
              for (final e in widget.equipos)
                DropdownMenuItem(
                  value: e,
                  enabled: e.sePuedeRetar,
                  child: Text(
                    e.sePuedeRetar ? e.name : '${e.name} — ${e.motivoNoRetable}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: e.sePuedeRetar ? null : Colors.grey.shade500,
                    ),
                  ),
                ),
            ],
            onChanged: (v) => setState(() => _rival = v ?? _rival),
          ),
          if (!_rival.sePuedeRetar) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.orange.shade800),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${_rival.name}: ${_rival.motivoNoRetable}. '
                    'Todavía no se le puede retar.',
                    style: TextStyle(
                        fontSize: 12, color: Colors.orange.shade900),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),

          OutlinedButton.icon(
            onPressed: _elegirCuando,
            icon: const Icon(Icons.event),
            label: Text(
              _cuando == null ? 'Elegir día y hora' : _fecha(_cuando!),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              foregroundColor: _verde,
            ),
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _lugar,
            decoration: const InputDecoration(
              labelText: 'Cancha (opcional)',
              prefixIcon: Icon(Icons.place),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _minutos,
                  decoration: const InputDecoration(
                    labelText: 'Minutos',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 60, child: Text('60')),
                    DropdownMenuItem(value: 70, child: Text('70')),
                    DropdownMenuItem(value: 80, child: Text('80')),
                    DropdownMenuItem(value: 90, child: Text('90')),
                  ],
                  onChanged: (v) => setState(() => _minutos = v ?? 90),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _cambios,
                  decoration: const InputDecoration(
                    labelText: 'Cambios',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final n in [3, 5, 7, 11])
                      DropdownMenuItem(value: n, child: Text('$n')),
                  ],
                  onChanged: (v) => setState(() => _cambios = v ?? 5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _mensaje,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Mensaje (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),

          FilledButton(
            onPressed: _cuando == null || !_rival.sePuedeRetar
                ? null
                : () => Navigator.pop(
                    context,
                    _Propuesta(
                      rivalId: _rival.id,
                      rivalNombre: _rival.name,
                      cuando: _cuando!,
                      lugar: _lugar.text.trim().isEmpty
                          ? null
                          : _lugar.text.trim(),
                      minutos: _minutos,
                      cambios: _cambios,
                      mensaje: _mensaje.text.trim().isEmpty
                          ? null
                          : _mensaje.text.trim(),
                    ),
                  ),
            style: FilledButton.styleFrom(
              backgroundColor: _verde,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('Enviar el reto'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
