import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/session.dart';

/// La puerta de entrada.
///
/// Una cuenta que no pertenece a ningún grupo no ve nada de la app: los
/// grupos son la frontera de privacidad, y sin uno no hay equipos,
/// partidos ni rankings que mostrar. Por eso esta pantalla no se puede
/// saltar mientras no tengas grupo.
///
/// Dos caminos: canjear una clave que te dieron, o crear tu propia liga.
class UnirseGrupoScreen extends StatefulWidget {
  const UnirseGrupoScreen({
    super.key,
    required this.session,
    this.puedeVolver = false,
  });

  final Session session;

  /// `false` cuando es la puerta obligatoria; `true` si se llega desde
  /// el perfil para sumarse a otro grupo.
  final bool puedeVolver;

  @override
  State<UnirseGrupoScreen> createState() => _UnirseGrupoScreenState();
}

class _UnirseGrupoScreenState extends State<UnirseGrupoScreen> {
  final _clave = TextEditingController();
  final _nombreGrupo = TextEditingController();

  bool _creando = false;
  String? _error;

  @override
  void dispose() {
    _clave.dispose();
    _nombreGrupo.dispose();
    super.dispose();
  }

  Future<void> _unirse() async {
    setState(() => _error = null);
    final error = await widget.session.unirseConCodigo(_clave.text);
    if (!mounted) return;

    if (error != null) {
      setState(() => _error = error);
      return;
    }
    _salir('Te uniste a ${widget.session.grupoActual?.name ?? "el grupo"}.');
  }

  Future<void> _crear() async {
    setState(() => _error = null);
    final nombre = _nombreGrupo.text.trim();
    if (nombre.length < 2) {
      setState(() => _error = 'Ponle un nombre al grupo.');
      return;
    }

    final error = await widget.session.crearGrupo(nombre: nombre);
    if (!mounted) return;

    if (error != null) {
      setState(() => _error = error);
      return;
    }
    _salir('Grupo "$nombre" creado. Ya puedes invitar a los demás.');
  }

  void _salir(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(mensaje),
      backgroundColor: Colors.green.shade700,
    ));
    if (widget.puedeVolver) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: widget.puedeVolver,
        title: Text(
          _creando ? 'Crear un grupo' : 'Unirse a un grupo',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1B5E20),
        foregroundColor: Colors.white,
      ),
      body: ListenableBuilder(
        listenable: widget.session,
        builder: (context, _) {
          final ocupado = widget.session.ocupado;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                const Icon(Icons.groups_2, size: 64, color: Color(0xFF1B5E20)),
                const SizedBox(height: 16),
                Text(
                  'Los grupos son privados',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Cada liga ve solo lo suyo. Para entrar necesitas la clave '
                  'de invitación de quien la administra.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                ),
                const SizedBox(height: 28),

                if (!_creando) ...[
                  TextField(
                    controller: _clave,
                    textCapitalization: TextCapitalization.characters,
                    textAlign: TextAlign.center,
                    maxLength: 8,
                    style: GoogleFonts.robotoMono(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 6,
                    ),
                    inputFormatters: [
                      // El código es de 8 caracteres en mayúscula, sin
                      // O/0 ni I/1 para poder dictarlo en voz alta.
                      FilteringTextInputFormatter.allow(
                          RegExp('[A-HJ-NP-Za-hj-np-z2-9]')),
                      _AMayusculas(),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Clave de invitación',
                      hintText: 'ABCD2345',
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                    onSubmitted: (_) => ocupado ? null : _unirse(),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: ocupado ? null : _unirse,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1B5E20),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: ocupado
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text('Entrar al grupo',
                            style:
                                GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                  ),
                ] else ...[
                  TextField(
                    controller: _nombreGrupo,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del grupo',
                      hintText: 'Liga Barrial Norte',
                      prefixIcon: Icon(Icons.emoji_events_outlined),
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => ocupado ? null : _crear(),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 18, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Quedarás como administrador y se generará una '
                            'clave para invitar a los demás equipos.',
                            style: TextStyle(
                                fontSize: 12, color: Colors.blue.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: ocupado ? null : _crear,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1B5E20),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: ocupado
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text('Crear el grupo',
                            style:
                                GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                  ),
                ],

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

                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: ocupado
                      ? null
                      : () => setState(() {
                            _creando = !_creando;
                            _error = null;
                          }),
                  child: Text(_creando
                      ? 'Tengo una clave de invitación'
                      : 'No tengo clave: quiero crear mi propio grupo'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// El código se guarda siempre en mayúscula, escriba como escriba.
class _AMayusculas extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue anterior,
    TextEditingValue nuevo,
  ) =>
      TextEditingValue(
        text: nuevo.text.toUpperCase(),
        selection: nuevo.selection,
      );
}
