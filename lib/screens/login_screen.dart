import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/cedula.dart';
import '../core/session.dart';
import '../models/models.dart';

/// Entrar o crear cuenta.
///
/// El registro pide todo de una vez: cédula, correo, contraseña y la
/// clave de invitación. Son un solo acto —"entro a la app"— y partirlo
/// en dos pantallas obligaba a explicar dos veces lo mismo.
///
/// La clave se comprueba mientras se escribe, antes de que exista la
/// cuenta, para que la persona sepa a qué liga o equipo va a entrar.
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
  final _cedula = TextEditingController();
  final _invitacion = TextEditingController();

  Timer? _rebote;
  ClaveRevisada? _revisada;
  bool _revisando = false;

  bool _registrando = false;
  bool _verClave = false;
  String? _error;
  String? _aviso;

  @override
  void initState() {
    super.initState();
    _invitacion.addListener(_alEscribirClave);
  }

  @override
  void dispose() {
    _rebote?.cancel();
    _correo.dispose();
    _clave.dispose();
    _nombre.dispose();
    _cedula.dispose();
    _invitacion.dispose();
    super.dispose();
  }

  /// Se consulta al servidor cuando el código está completo, tras una
  /// pausa corta. No en cada tecla, y solo si tiene forma de invitación.
  void _alEscribirClave() {
    _rebote?.cancel();
    if (!Session.pareceInvitacion(_invitacion.text)) {
      if (_revisada != null) setState(() => _revisada = null);
      return;
    }

    _rebote = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _revisando = true);
      final r = await widget.session.revisarClave(_invitacion.text);
      if (!mounted) return;
      setState(() {
        _revisada = r;
        _revisando = false;
      });
    });
  }

  Future<void> _enviar() async {
    setState(() {
      _error = null;
      _aviso = null;
    });
    if (!_formulario.currentState!.validate()) return;

    final correo = _correo.text.trim();
    final clave = _clave.text;

    if (!_registrando) {
      final error = await widget.session.entrar(correo: correo, clave: clave);
      if (!mounted) return;
      if (error != null) {
        setState(() => _error = error);
        return;
      }
      Navigator.of(context).pop();
      return;
    }

    // Registro: crear la cuenta y canjear la clave en un solo paso.
    final error = await widget.session.registrarse(
      correo: correo,
      clave: clave,
      cedula: _cedula.text.trim(),
      nombreVisible: _nombre.text.trim().isEmpty ? null : _nombre.text.trim(),
    );
    if (!mounted) return;

    if (error != null) {
      setState(() => _error = error);
      return;
    }

    // Con confirmación de correo activada, el registro no deja sesión
    // abierta y la clave no se puede canjear todavía.
    if (!widget.session.haySesion) {
      setState(() {
        _registrando = false;
        _aviso = 'Cuenta creada. Confirma tu correo, inicia sesión y te '
            'pediremos la clave de invitación.';
      });
      return;
    }

    final errorClave = await widget.session.canjearClave(_invitacion.text);
    if (!mounted) return;

    if (errorClave != null) {
      // La cuenta ya existe: no se pierde porque la clave falle. La
      // puerta se la volverá a pedir.
      setState(() => _aviso =
          'Tu cuenta se creó, pero la clave no se pudo canjear: $errorClave');
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
                  const Icon(Icons.sports_soccer, size: 56, color: Color(0xFF1B5E20)),
                  const SizedBox(height: 12),
                  Text(
                    _registrando
                        ? 'Tu cédula te vincula con tu ficha; la clave, con tu liga.'
                        : 'Entra para registrar goles y jugadores',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                  ),
                  const SizedBox(height: 24),

                  if (_registrando) ...[
                    TextFormField(
                      controller: _cedula,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(10),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Cédula',
                        prefixIcon: Icon(Icons.badge_outlined),
                        border: OutlineInputBorder(),
                        helperText: 'Con ella recibes tu ficha si tu capitán ya te cargó',
                        helperMaxLines: 2,
                        counterText: '',
                      ),
                      // Se valida aquí y también en la base: una
                      // validación que solo vive en el cliente no es
                      // validación, cualquiera puede llamar a la API.
                      validator: Cedula.error,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nombre,
                      textInputAction: TextInputAction.next,
                      textCapitalization: TextCapitalization.words,
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
                    textInputAction:
                        _registrando ? TextInputAction.next : TextInputAction.done,
                    onFieldSubmitted: (_) =>
                        (ocupado || _registrando) ? null : _enviar(),
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

                  if (_registrando) ...[
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 12),
                    Text(
                      'Clave de acceso',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'La de tu liga, la de tu equipo o la de desarrollo: '
                      'la app reconoce cuál es.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _invitacion,
                      textAlign: TextAlign.center,
                      // Ni tope de 8 ni filtro de caracteres: la clave de
                      // desarrollo es una contraseña larga, y con el filtro
                      // de las invitaciones ni siquiera se podía teclear
                      // (descartaba el 1 y el 0).
                      style: GoogleFonts.robotoMono(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
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
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : null,
                      ),
                      validator: (v) {
                        final t = (v ?? '').trim();
                        // Dos formas válidas y disjuntas: invitación de
                        // ocho caracteres, o clave de desarrollo de doce
                        // dígitos o más.
                        if (!Session.pareceInvitacion(t) &&
                            !Session.pareceClaveDev(t)) {
                          return 'Escribe la clave completa';
                        }
                        // Solo se comprueba contra el servidor lo que tiene
                        // forma de invitación. La de desarrollo se verifica
                        // al canjearla: no hay forma de consultarla sin
                        // convertirla en un oráculo de fuerza bruta.
                        final r = _revisada;
                        if (Session.pareceInvitacion(t) && r != null && !r.valida) {
                          return r.motivo;
                        }
                        return null;
                      },
                    ),

                    if (_revisada != null) ...[
                      const SizedBox(height: 4),
                      _VistaPrevia(revisada: _revisada!),
                    ],
                  ],

                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    _Mensaje(texto: _error!, esError: true),
                  ],
                  if (_aviso != null) ...[
                    const SizedBox(height: 16),
                    _Mensaje(texto: _aviso!, esError: false),
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
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            _registrando ? 'Crear cuenta y entrar' : 'Entrar',
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600),
                          ),
                  ),

                  const SizedBox(height: 12),

                  TextButton(
                    onPressed: ocupado
                        ? null
                        : () => setState(() {
                              _registrando = !_registrando;
                              _error = null;
                              _aviso = null;
                            }),
                    child: Text(_registrando
                        ? '¿Ya tienes cuenta? Inicia sesión'
                        : '¿No tienes cuenta? Créala'),
                  ),

                  if (_registrando) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Si eres capitán, la clave de la liga te la da quien '
                      'administra la app. Si eres jugador, te la da tu capitán.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Qué hace la clave, antes de crear la cuenta.
class _VistaPrevia extends StatelessWidget {
  const _VistaPrevia({required this.revisada});

  final ClaveRevisada revisada;

  @override
  Widget build(BuildContext context) {
    final ok = revisada.valida;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ok ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
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
            size: 18,
            color: ok ? Colors.green.shade800 : Colors.orange.shade800,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              ok ? (revisada.descripcion ?? '') : (revisada.motivo ?? ''),
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _Mensaje extends StatelessWidget {
  const _Mensaje({required this.texto, required this.esError});

  final String texto;
  final bool esError;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: esError ? Colors.red.shade50 : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: esError ? Colors.red.shade200 : Colors.blue.shade200),
      ),
      child: Row(
        children: [
          Icon(esError ? Icons.error_outline : Icons.info_outline,
              size: 18,
              color: esError ? Colors.red.shade700 : Colors.blue.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(texto,
                style: TextStyle(
                    color: esError ? Colors.red.shade900 : Colors.blue.shade900,
                    fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
