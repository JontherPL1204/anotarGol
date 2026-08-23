import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/models.dart';
import '../repositories/repositories.dart';
import 'dev_panel_screen.dart';

/// La entrada al panel de desarrollo.
///
/// Hace dos cosas según quién llegue:
///
///   * Si la cuenta **todavía no es dev**, la clave la convierte en dev.
///     Eso es poder total sobre la plataforma, y la pantalla lo dice
///     antes de que se escriba nada.
///   * Si **ya es dev**, la clave solo abre el panel por un rato.
///
/// La base no lanza excepción cuando la clave está mal: devuelve el
/// motivo. Por eso aquí se muestran mensajes y no errores crudos.
class DevAccesoScreen extends StatefulWidget {
  const DevAccesoScreen({super.key, this.dev = const DevRepository()});

  final DevRepository dev;

  @override
  State<DevAccesoScreen> createState() => _DevAccesoScreenState();
}

class _DevAccesoScreenState extends State<DevAccesoScreen> {
  final _clave = TextEditingController();

  PanelDev _estado = const PanelDev();
  bool _cargando = true;
  bool _enviando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarEstado();
  }

  @override
  void dispose() {
    _clave.dispose();
    super.dispose();
  }

  Future<void> _cargarEstado() async {
    try {
      final e = await widget.dev.estado();
      if (!mounted) return;
      setState(() {
        _estado = e;
        _cargando = false;
      });
      if (e.abierto) _entrarAlPanel();
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _entrarAlPanel() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => DevPanelScreen(dev: widget.dev)),
    );
  }

  Future<void> _enviar() async {
    final codigo = _clave.text.trim();
    if (codigo.isEmpty) {
      setState(() => _error = 'Escribe la clave.');
      return;
    }

    setState(() {
      _enviando = true;
      _error = null;
    });

    try {
      // Ser dev ya, o no serlo, cambia lo que hace la clave.
      final r = _estado.soyDev
          ? await widget.dev.abrirPanel(codigo: codigo)
          : await widget.dev.canjearClaveDev(codigo);

      if (!mounted) return;

      if (!r.ok) {
        setState(() {
          _enviando = false;
          _error = r.motivo ?? 'No se pudo entrar.';
        });
        await _cargarEstado();
        return;
      }

      _entrarAlPanel();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _error = 'No se pudo conectar.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final yaEsDev = _estado.soyDev;

    return Scaffold(
      appBar: AppBar(
        title: Text(yaEsDev ? 'Abrir el panel' : 'Clave de acceso',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blueGrey.shade900,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Icon(yaEsDev ? Icons.lock_open : Icons.shield_moon,
                size: 60, color: Colors.blueGrey.shade700),
            const SizedBox(height: 16),
            Text(
              yaEsDev ? 'Panel de desarrollo' : '¿Tienes una clave de acceso?',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),

            // Quien no es dev tiene que saber qué está a punto de hacer.
            if (!yaEsDev)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade400),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Colors.amber.shade800, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Una clave válida convierte esta cuenta en cuenta de '
                        'desarrollo: podrá ver y editar todas las ligas, todos '
                        'los equipos y todos los chats, y borrar ligas enteras.',
                        style: TextStyle(
                            fontSize: 12, color: Colors.brown.shade900),
                      ),
                    ),
                  ],
                ),
              )
            else
              Text(
                _estado.hayClave
                    ? 'Escribe la clave del panel. Se abre por 30 minutos y '
                        'se cierra solo.'
                    : 'No hay clave de panel definida: entra directamente.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),

            const SizedBox(height: 24),

            if (_estado.bloqueado)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.block, color: Colors.red.shade700, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Demasiados intentos. Espera unos minutos antes de '
                        'volver a probar.',
                        style: TextStyle(
                            fontSize: 13, color: Colors.red.shade900),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              TextField(
                controller: _clave,
                obscureText: true,
                autofocus: true,
                style: GoogleFonts.robotoMono(fontSize: 16),
                decoration: const InputDecoration(
                  labelText: 'Clave',
                  prefixIcon: Icon(Icons.key),
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _enviando ? null : _enviar(),
              ),

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

              const SizedBox(height: 12),
              if (_estado.intentos > 0 && !_estado.bloqueado)
                Text(
                  'Intentos fallidos: ${_estado.intentos} de 5',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),

              const SizedBox(height: 12),
              FilledButton(
                onPressed: _enviando ? null : _enviar,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.blueGrey.shade900,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _enviando
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(yaEsDev ? 'Abrir el panel' : 'Canjear la clave',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
              ),
            ],

            const SizedBox(height: 28),
            Text(
              'Si no tienes clave, esta pantalla no hace nada. No es un '
              'atajo: sin una clave válida no pasa nada.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}
