import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/session.dart';

/// Entrar o crear cuenta.
///
/// Un solo formulario con dos modos, en vez de dos pantallas: es el mismo
/// par de campos y evita que el usuario se pierda buscando "registrarse".
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.session});

  final Session session;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formulario = GlobalKey<FormState>();
  final _correo = TextEditingController();
  final _clave = TextEditingController();
  final _nombre = TextEditingController();

  bool _registrando = false;
  bool _verClave = false;
  String? _error;

  @override
  void dispose() {
    _correo.dispose();
    _clave.dispose();
    _nombre.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    setState(() => _error = null);
    if (!_formulario.currentState!.validate()) return;

    final correo = _correo.text.trim();
    final clave = _clave.text;

    final error = _registrando
        ? await widget.session.registrarse(
            correo: correo,
            clave: clave,
            nombreVisible: _nombre.text.trim().isEmpty ? null : _nombre.text.trim(),
          )
        : await widget.session.entrar(correo: correo, clave: clave);

    if (!mounted) return;

    if (error != null) {
      setState(() => _error = error);
      return;
    }

    // Con confirmacion de correo activada, el registro no deja sesion
    // abierta: hay que avisarlo en vez de devolver una pantalla muda.
    if (_registrando && !widget.session.haySesion) {
      setState(() {
        _registrando = false;
        _error = 'Cuenta creada. Revisa tu correo para confirmarla y luego inicia sesión.';
      });
      return;
    }

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _registrando ? 'Crear cuenta' : 'Iniciar sesión',
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
            child: Form(
              key: _formulario,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  const Icon(Icons.sports_soccer, size: 64, color: Color(0xFF1B5E20)),
                  const SizedBox(height: 12),
                  Text(
                    _registrando
                        ? 'Crea tu cuenta para administrar el club'
                        : 'Entra para registrar goles y jugadores',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 28),

                  if (_registrando) ...[
                    TextFormField(
                      controller: _nombre,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Tu nombre (opcional)',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  TextFormField(
                    controller: _correo,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Correo',
                      prefixIcon: Icon(Icons.alternate_email),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return 'Escribe tu correo';
                      if (!t.contains('@') || !t.contains('.')) {
                        return 'Ese correo no parece válido';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _clave,
                    obscureText: !_verClave,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => ocupado ? null : _enviar(),
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_verClave ? Icons.visibility_off : Icons.visibility),
                        tooltip: _verClave ? 'Ocultar' : 'Mostrar',
                        onPressed: () => setState(() => _verClave = !_verClave),
                      ),
                    ),
                    validator: (v) {
                      if ((v ?? '').isEmpty) return 'Escribe tu contraseña';
                      if (_registrando && v!.length < 6) {
                        return 'Usa al menos 6 caracteres';
                      }
                      return null;
                    },
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
                          Icon(Icons.info_outline, size: 18, color: Colors.red.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(color: Colors.red.shade900, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  FilledButton(
                    onPressed: ocupado ? null : _enviar,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1B5E20),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: ocupado
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _registrando ? 'Crear cuenta' : 'Entrar',
                            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                          ),
                  ),

                  const SizedBox(height: 12),

                  TextButton(
                    onPressed: ocupado
                        ? null
                        : () => setState(() {
                              _registrando = !_registrando;
                              _error = null;
                            }),
                    child: Text(_registrando
                        ? '¿Ya tienes cuenta? Inicia sesión'
                        : '¿No tienes cuenta? Créala'),
                  ),

                  const SizedBox(height: 8),
                  Text(
                    'Sin cuenta también puedes ver la plantilla y el marcador.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
