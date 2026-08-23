import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../core/session.dart';
import '../repositories/repositories.dart';
import 'plantilla_inicial_screen.dart';

/// El primer paso del capitán: ponerle nombre y escudo a su equipo.
///
/// El nombre es obligatorio. El escudo no: si no lo pone, nunca se abre
/// el selector de imágenes y el equipo queda con su color.
class FundarEquipoScreen extends StatefulWidget {
  const FundarEquipoScreen({
    super.key,
    required this.session,
    required this.groupId,
    this.capitan = const CapitanRepository(),
    this.selector,
  });

  final Session session;
  final String groupId;
  final CapitanRepository capitan;

  /// Se inyecta en las pruebas para no abrir la galería de verdad.
  final Future<XFile?> Function()? selector;

  @override
  State<FundarEquipoScreen> createState() => _FundarEquipoScreenState();
}

class _FundarEquipoScreenState extends State<FundarEquipoScreen> {
  final _formulario = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _corto = TextEditingController();

  XFile? _escudo;
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _nombre.dispose();
    _corto.dispose();
    super.dispose();
  }

  Future<void> _elegirEscudo() async {
    try {
      final elegir = widget.selector ??
          () => ImagePicker().pickImage(
                source: ImageSource.gallery,
                maxWidth: 512,
                maxHeight: 512,
                imageQuality: 85,
              );

      final imagen = await elegir();
      if (imagen != null && mounted) setState(() => _escudo = imagen);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo abrir la galería. El escudo es opcional: '
            'puedes crear el equipo sin él y ponerlo después.');
      }
    }
  }

  Future<void> _fundar() async {
    if (!_formulario.currentState!.validate()) return;

    setState(() {
      _guardando = true;
      _error = null;
    });

    try {
      final equipo = await widget.capitan.fundarEquipo(
        groupId: widget.groupId,
        nombre: _nombre.text.trim(),
        nombreCorto: _corto.text.trim().isEmpty ? null : _corto.text.trim(),
      );

      // El escudo va después de crear el equipo: la ruta del archivo
      // lleva su id, y las políticas de storage lo exigen así.
      if (_escudo != null) {
        try {
          final bytes = await _escudo!.readAsBytes();
          final ext = _escudo!.name.split('.').last.toLowerCase();
          final url = await widget.capitan.subirEscudo(
            teamId: equipo.id,
            bytes: bytes,
            extension: ext.isEmpty ? 'png' : ext,
          );
          await widget.capitan.actualizarIdentidad(
            teamId: equipo.id,
            nombre: equipo.name,
            nombreCorto: equipo.shortName,
            logoUrl: url,
          );
        } catch (_) {
          // El equipo ya existe: no se pierde por un escudo que no subió.
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('El equipo se creó, pero el escudo no se pudo subir. '
                  'Puedes ponerlo más tarde.'),
            ));
          }
        }
      }

      await widget.session.cargarSituacion();
      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PlantillaInicialScreen(
            session: widget.session,
            teamId: equipo.id,
            nombreEquipo: equipo.name,
            capitan: widget.capitan,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = _traducir(e.toString());
      });
    }
  }

  String _traducir(String bruto) {
    final m = bruto.toLowerCase();
    if (m.contains('clave de capitán') || m.contains('clave de capitan')) {
      return 'Necesitas una clave de capitán para fundar un equipo en esta liga.';
    }
    if (m.contains('no perteneces a ese grupo')) {
      return 'No perteneces a esta liga.';
    }
    if (m.contains('ya fundaste')) {
      return 'Ya fundaste tu equipo en esta liga.';
    }
    if (m.contains('duplicate') || m.contains('unique')) {
      return 'Ya existe un equipo con ese nombre.';
    }
    return 'No se pudo crear el equipo. Revisa tu conexión.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Fundar mi equipo',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1B5E20),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formulario,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: _BotonEscudo(escudo: _escudo, onTap: _elegirEscudo)),
              const SizedBox(height: 8),
              Text(
                _escudo == null ? 'Escudo (opcional)' : 'Toca para cambiarlo',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 28),

              TextFormField(
                controller: _nombre,
                textCapitalization: TextCapitalization.words,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nombre del equipo',
                  hintText: 'Halcones FC',
                  prefixIcon: Icon(Icons.shield_outlined),
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.length < 2) return 'Tu equipo necesita un nombre';
                  if (t.length > 80) return 'Ese nombre es muy largo';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _corto,
                textCapitalization: TextCapitalization.characters,
                maxLength: 12,
                decoration: const InputDecoration(
                  labelText: 'Abreviatura (opcional)',
                  hintText: 'HAL',
                  prefixIcon: Icon(Icons.short_text),
                  border: OutlineInputBorder(),
                  counterText: '',
                  helperText: 'Para cuando no entra el nombre completo',
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          size: 18, color: Colors.red.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_error!,
                            style: TextStyle(
                                color: Colors.red.shade900, fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),
              FilledButton(
                onPressed: _guardando ? null : _fundar,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1B5E20),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _guardando
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text('Crear y cargar la plantilla',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
              ),

              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Después vas a necesitar la cédula de tus 11 jugadores. '
                        'Con ella, cada uno recibe su ficha al crear su cuenta.',
                        style:
                            TextStyle(fontSize: 12, color: Colors.blue.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BotonEscudo extends StatelessWidget {
  const _BotonEscudo({required this.escudo, required this.onTap});

  final XFile? escudo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 110,
        height: 110,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.grey.shade100,
          border: Border.all(color: Colors.grey.shade400, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: escudo == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo_outlined,
                      size: 30, color: Colors.grey.shade600),
                  const SizedBox(height: 4),
                  Text('Escudo',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ],
              )
            : Image.network(
                escudo!.path,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Icon(Icons.shield,
                    size: 40, color: Colors.green.shade700),
              ),
      ),
    );
  }
}
