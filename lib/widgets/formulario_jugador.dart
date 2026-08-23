import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/models.dart';

/// Lo que devuelve el formulario.
class DatosJugador {
  const DatosJugador({
    required this.nombre,
    required this.posicion,
    this.dorsal,
    this.detallePosicion,
  });

  final String nombre;
  final int? dorsal;
  final PlayerPosition posicion;
  final String? detallePosicion;
}

/// Detalles sugeridos por linea, para no obligar a escribir a mano
/// "Lateral Derecho" cada vez.
const Map<PlayerPosition, List<String>> detallesPorPosicion = {
  PlayerPosition.gk: ['Portero'],
  PlayerPosition.df: [
    'Defensa Central',
    'Lateral Derecho',
    'Lateral Izquierdo',
    'Líbero',
  ],
  PlayerPosition.mf: [
    'Mediocampista Defensivo',
    'Mediocampista Central',
    'Mediocampista Ofensivo',
    'Volante Mixto',
  ],
  PlayerPosition.fw: [
    'Delantero Centro',
    'Extremo Derecho',
    'Extremo Izquierdo',
    'Segundo Delantero',
  ],
};

/// Abre el formulario de jugador y devuelve los datos, o `null` si se
/// cancela. Sirve igual para la plantilla propia y para la del rival.
Future<DatosJugador?> mostrarFormularioJugador(
  BuildContext context, {
  String titulo = 'Nuevo jugador',
  String? nombre,
  int? dorsal,
  PlayerPosition posicion = PlayerPosition.mf,
  String? detallePosicion,
  List<int> dorsalesOcupados = const [],
}) {
  return showModalBottomSheet<DatosJugador>(
    context: context,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _FormularioJugador(
        titulo: titulo,
        nombre: nombre,
        dorsal: dorsal,
        posicion: posicion,
        detallePosicion: detallePosicion,
        dorsalesOcupados: dorsalesOcupados,
      ),
    ),
  );
}

class _FormularioJugador extends StatefulWidget {
  const _FormularioJugador({
    required this.titulo,
    required this.posicion,
    required this.dorsalesOcupados,
    this.nombre,
    this.dorsal,
    this.detallePosicion,
  });

  final String titulo;
  final String? nombre;
  final int? dorsal;
  final PlayerPosition posicion;
  final String? detallePosicion;
  final List<int> dorsalesOcupados;

  @override
  State<_FormularioJugador> createState() => _FormularioJugadorState();
}

class _FormularioJugadorState extends State<_FormularioJugador> {
  final _formulario = GlobalKey<FormState>();
  late final TextEditingController _nombre =
      TextEditingController(text: widget.nombre ?? '');
  late final TextEditingController _dorsal =
      TextEditingController(text: widget.dorsal?.toString() ?? '');

  late PlayerPosition _posicion = widget.posicion;
  late String? _detalle = widget.detallePosicion;

  @override
  void dispose() {
    _nombre.dispose();
    _dorsal.dispose();
    super.dispose();
  }

  void _guardar() {
    if (!_formulario.currentState!.validate()) return;

    Navigator.pop(
      context,
      DatosJugador(
        nombre: _nombre.text.trim(),
        dorsal: int.tryParse(_dorsal.text.trim()),
        posicion: _posicion,
        detallePosicion: _detalle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sugerencias = detallesPorPosicion[_posicion] ?? const <String>[];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formulario,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.titulo,
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),

              TextFormField(
                controller: _nombre,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nombre y apellido',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.length < 2) return 'Escribe el nombre del jugador';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _dorsal,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                ],
                decoration: const InputDecoration(
                  labelText: 'Dorsal (1 a 99)',
                  prefixIcon: Icon(Icons.tag),
                  border: OutlineInputBorder(),
                  helperText: 'Puedes dejarlo vacío si aún no tiene número',
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return null;
                  final n = int.tryParse(t);
                  if (n == null || n < 1 || n > 99) return 'Usa un número del 1 al 99';
                  if (widget.dorsalesOcupados.contains(n)) {
                    return 'El dorsal $n ya está ocupado';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              Text('Posición', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SegmentedButton<PlayerPosition>(
                segments: const [
                  ButtonSegment(value: PlayerPosition.gk, label: Text('POR')),
                  ButtonSegment(value: PlayerPosition.df, label: Text('DEF')),
                  ButtonSegment(value: PlayerPosition.mf, label: Text('MED')),
                  ButtonSegment(value: PlayerPosition.fw, label: Text('DEL')),
                ],
                selected: {_posicion},
                onSelectionChanged: (s) => setState(() {
                  _posicion = s.first;
                  // El detalle viejo ya no aplica a la nueva linea.
                  if (!(detallesPorPosicion[_posicion] ?? []).contains(_detalle)) {
                    _detalle = null;
                  }
                }),
              ),

              if (sugerencias.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final s in sugerencias)
                      ChoiceChip(
                        label: Text(s, style: const TextStyle(fontSize: 12)),
                        selected: _detalle == s,
                        onSelected: (sel) =>
                            setState(() => _detalle = sel ? s : null),
                      ),
                  ],
                ),
              ],

              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _guardar,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1B5E20),
                      ),
                      child: const Text('Guardar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
