import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/session.dart';
import '../models/models.dart';

/// La puerta de entrada: escribir la clave de invitación.
///
/// Una cuenta que no pertenece a ninguna liga no ve nada de la app, así
/// que esta pantalla no se puede saltar mientras no haya grupo.
///
/// Hay una sola casilla, aunque existan dos tipos de clave. Quien recibe
/// un código por WhatsApp no sabe si es de liga o de equipo, y no tiene
/// por qué saberlo: el sistema lo averigua. Lo que sí se le muestra,
/// antes de confirmar, es **qué le va a pasar** con esa clave.
class ClaveScreen extends StatefulWidget {
  const ClaveScreen({
    super.key,
    required this.session,
    this.puedeVolver = false,
  });

  final Session session;

  /// `false` cuando es la puerta obligatoria; `true` si se llega desde
  /// el perfil para sumarse a otra liga o a otro equipo.
  final bool puedeVolver;

  @override
  State<ClaveScreen> createState() => _ClaveScreenState();
}

class _ClaveScreenState extends State<ClaveScreen> {
  final _clave = TextEditingController();

  Timer? _rebote;
  ClaveRevisada? _revisada;
  bool _revisando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _clave.addListener(_alEscribir);
  }

  @override
  void dispose() {
    _rebote?.cancel();
    _clave.dispose();
    super.dispose();
  }

  /// Se consulta al servidor mientras escribe, pero no en cada tecla:
  /// solo cuando el código está completo y tras una pausa corta.
  void _alEscribir() {
    _rebote?.cancel();
    final texto = _clave.text.trim();

    if (texto.length < 8) {
      if (_revisada != null) setState(() => _revisada = null);
      return;
    }

    _rebote = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _revisando = true);
      final r = await widget.session.revisarClave(texto);
      if (!mounted) return;
      setState(() {
        _revisada = r;
        _revisando = false;
        _error = null;
      });
    });
  }

  Future<void> _entrar() async {
    final codigo = _clave.text.trim();
    if (codigo.length < 8) {
      setState(() => _error = 'La clave son 8 caracteres.');
      return;
    }

    setState(() => _error = null);
    final error = await widget.session.canjearClave(codigo);
    if (!mounted) return;

    if (error != null) {
      setState(() => _error = error);
      return;
    }

    final s = widget.session.situacion;
    final mensaje = s.tieneEquipo
        ? 'Ya estás en ${s.equipo}.'
        : s.puedeFundar
            ? 'Entraste a ${s.grupo}. Ahora funda tu equipo.'
            : 'Entraste a ${s.grupo}.';

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
        title: Text('Clave de invitación',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1B5E20),
        foregroundColor: Colors.white,
      ),
      body: ListenableBuilder(
        listenable: widget.session,
        builder: (context, _) {
          final ocupado = widget.session.ocupado;
          final r = _revisada;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                const Icon(Icons.vpn_key, size: 60, color: Color(0xFF1B5E20)),
                const SizedBox(height: 16),
                Text(
                  'Las ligas son privadas',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Escribe la clave que te dieron. Sirve tanto la de la liga '
                  'como la de tu equipo: la app reconoce cuál es.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                ),
                const SizedBox(height: 28),

                TextField(
                  controller: _clave,
                  textCapitalization: TextCapitalization.characters,
                  textAlign: TextAlign.center,
                  maxLength: 8,
                  autofocus: true,
                  style: GoogleFonts.robotoMono(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 6,
                  ),
                  inputFormatters: [
                    // El alfabeto del código no tiene O/0 ni I/1, para
                    // poder dictarlo en voz alta sin confusión.
                    FilteringTextInputFormatter.allow(
                        RegExp('[A-HJ-NP-Za-hj-np-z2-9]')),
                    _AMayusculas(),
                  ],
                  decoration: InputDecoration(
                    hintText: 'ABCD2345',
                    border: const OutlineInputBorder(),
                    counterText: '',
                    suffixIcon: _revisando
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                  ),
                  onSubmitted: (_) => ocupado ? null : _entrar(),
                ),

                // Qué va a pasar con esa clave, antes de confirmarla.
                if (r != null) ...[
                  const SizedBox(height: 8),
                  _Vista(revisada: r),
                ],

                if (_error != null) ...[
                  const SizedBox(height: 12),
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

                FilledButton(
                  onPressed:
                      (ocupado || r == null || !r.valida) ? null : _entrar,
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
                      : Text(
                          r != null && r.llevaAEquipo
                              ? 'Entrar a ${r.equipo}'
                              : 'Entrar',
                          style:
                              GoogleFonts.poppins(fontWeight: FontWeight.w600),
                        ),
                ),

                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 12),
                Text(
                  '¿No tienes clave?',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Text(
                  'Si eres capitán, pídesela a quien administra la app. '
                  'Si eres jugador, te la da el capitán de tu equipo.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// El anticipo de lo que hace la clave.
class _Vista extends StatelessWidget {
  const _Vista({required this.revisada});

  final ClaveRevisada revisada;

  @override
  Widget build(BuildContext context) {
    final ok = revisada.valida;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ok ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: ok ? Colors.green.shade300 : Colors.orange.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok
                ? (revisada.llevaAEquipo ? Icons.shield : Icons.emoji_events)
                : Icons.info_outline,
            color: ok ? Colors.green.shade800 : Colors.orange.shade800,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ok ? (revisada.descripcion ?? '') : (revisada.motivo ?? ''),
                  style: GoogleFonts.poppins(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                if (ok && revisada.haceCapitan) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Vas a necesitar las cédulas de tus 11 jugadores.',
                    style: TextStyle(
                        fontSize: 11, color: Colors.green.shade900),
                  ),
                ],
              ],
            ),
          ),
        ],
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
