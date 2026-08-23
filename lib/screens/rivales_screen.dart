import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/session.dart';
import '../data/club_admin.dart';
import '../models/models.dart';
import '../widgets/estado_vacio.dart';
import '../repositories/repositories.dart';
import 'equipo_liga_screen.dart';
import 'rival_plantilla_screen.dart';

/// Los equipos contra los que se puede jugar.
///
/// Dos listas, porque son dos cosas distintas:
///
///   * **Los equipos de tu liga.** Salen todos, completos o no: saber a
///     quién le faltan jugadores es parte de saber a quién puedes retar.
///     Su plantilla se abre cuando el partido queda concretado.
///   * **Otros rivales.** Los que el club carga a mano para amistosos
///     contra gente que no está en la app. Si no tienes sus datos, se
///     inventa la plantilla y queda marcada como inventada.
class RivalesScreen extends StatefulWidget {
  const RivalesScreen({super.key, required this.admin, this.session});

  final ClubAdmin admin;
  final Session? session;

  @override
  State<RivalesScreen> createState() => _RivalesScreenState();
}

class _RivalesScreenState extends State<RivalesScreen> {
  late Future<List<Rival>> _carga = widget.admin.equiposRivales();
  late Future<List<EquipoDelGrupo>> _liga = _cargarLiga();

  Future<List<EquipoDelGrupo>> _cargarLiga() async {
    final g = widget.session?.situacion.groupId;
    if (g == null) return const [];
    try {
      return await const ChallengesRepository().equiposParaRetar(g);
    } catch (_) {
      return const [];
    }
  }

  bool get _puedeEditar =>
      (widget.session?.puedeEditarPlantilla ?? false) &&
      widget.admin.disponible;

  Future<void> _recargar() async {
    final futuro = widget.admin.equiposRivales();
    final liga = _cargarLiga();
    setState(() {
      _carga = futuro;
      _liga = liga;
    });
    await futuro.catchError((_) => <Rival>[]);
    await liga;
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

  Future<void> _crear() async {
    final resultado = await showModalBottomSheet<(String, bool)>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: const _FormularioRival(),
      ),
    );
    if (resultado == null) return;

    final (nombre, inventar) = resultado;
    try {
      await widget.admin.crearRival(
        nombre: nombre,
        inventarPlantilla: inventar,
      );
      _avisar(
        inventar
            ? '$nombre creado con una plantilla inventada.'
            : '$nombre creado. Agrega sus jugadores cuando los tengas.',
      );
      await _recargar();
    } catch (_) {
      _avisar('No se pudo crear el rival. Revisa tus permisos.', error: true);
    }
  }

  Future<void> _eliminar(Rival rival) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Borrar ${rival.name}?'),
        content: const Text('Se borra el rival y toda su plantilla.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await widget.admin.eliminarRival(rival.id);
      _avisar('${rival.name} borrado.');
      await _recargar();
    } catch (_) {
      _avisar('No se pudo borrar.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Equipos rivales',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1B5E20),
        foregroundColor: Colors.white,
      ),
      floatingActionButton: _puedeEditar
          ? FloatingActionButton.extended(
              onPressed: _crear,
              backgroundColor: const Color(0xFF1B5E20),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Nuevo rival'),
            )
          : null,
      body: FutureBuilder<List<Rival>>(
        future: _carga,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // Que fallen los rivales cargados a mano no puede tapar los
          // equipos de la liga, que es lo que casi siempre se viene a ver.
          final rivales = snapshot.hasError
              ? const <Rival>[]
              : (snapshot.data ?? const <Rival>[]);

          return RefreshIndicator(
            onRefresh: _recargar,
            child: FutureBuilder<List<EquipoDelGrupo>>(
              future: _liga,
              builder: (context, snapLiga) {
                final equipos = snapLiga.data ?? const <EquipoDelGrupo>[];

                if (equipos.isEmpty && rivales.isEmpty) {
                  return ListView(
                    children: [
                      const SizedBox(height: 60),
                      EstadoVacio(
                        icono: Icons.shield_outlined,
                        titulo: 'Todavía no hay rivales',
                        mensaje: _puedeEditar
                            ? 'Cuando haya más equipos en tu liga aparecerán '
                                  'aquí. También puedes cargar uno a mano.'
                            : 'Aquí aparecerán los equipos contra los que '
                                  'juega el club.',
                      ),
                    ],
                  );
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                  children: [
                    if (equipos.isNotEmpty) ...[
                      const _Titulo('Equipos de tu liga'),
                      for (final e in equipos)
                        _TarjetaEquipoLiga(
                          equipo: e,
                          onAbrir: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => EquipoLigaScreen(equipo: e),
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),
                    ],
                    const _Titulo('Otros rivales'),
                    if (rivales.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 8,
                        ),
                        child: Text(
                          _puedeEditar
                              ? 'Para amistosos contra equipos que no están '
                                    'en la app. Si no sabes quiénes juegan, se '
                                    'inventa la plantilla.'
                              : 'Todavía no hay ninguno.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    for (final r in rivales)
                      _TarjetaRival(
                        rival: r,
                        puedeBorrar: _puedeEditar,
                        onAbrir: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RivalPlantillaScreen(
                                rival: r,
                                admin: widget.admin,
                                session: widget.session,
                              ),
                            ),
                          );
                          await _recargar();
                        },
                        onBorrar: () => _eliminar(r),
                      ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _TarjetaRival extends StatelessWidget {
  const _TarjetaRival({
    required this.rival,
    required this.puedeBorrar,
    required this.onAbrir,
    required this.onBorrar,
  });

  final Rival rival;
  final bool puedeBorrar;
  final VoidCallback onAbrir;
  final VoidCallback onBorrar;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        onTap: onAbrir,
        leading: CircleAvatar(
          backgroundColor: Colors.blueGrey.shade600,
          foregroundColor: Colors.white,
          child: const Icon(Icons.shield_outlined),
        ),
        title: Text(
          rival.name,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                rival.sinPlantilla
                    ? 'Sin jugadores cargados'
                    : '${rival.totalJugadores} jugadores',
              ),
              if (rival.totalImaginarios > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.shade600),
                  ),
                  child: Text(
                    rival.plantillaEsInventada
                        ? 'Plantilla inventada'
                        : '${rival.totalImaginarios} inventados',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.brown.shade800,
                    ),
                  ),
                ),
            ],
          ),
        ),
        trailing: puedeBorrar
            ? IconButton(
                onPressed: onBorrar,
                icon: const Icon(Icons.delete_outline),
                color: Colors.grey.shade600,
                tooltip: 'Borrar rival',
              )
            : const Icon(Icons.chevron_right),
      ),
    );
  }
}

/// Alta de rival. La pregunta central es si se tienen los datos o no.
class _FormularioRival extends StatefulWidget {
  const _FormularioRival();

  @override
  State<_FormularioRival> createState() => _FormularioRivalState();
}

class _FormularioRivalState extends State<_FormularioRival> {
  final _formulario = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  bool _inventar = true;

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                'Nuevo equipo rival',
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
                  labelText: 'Nombre del equipo',
                  prefixIcon: Icon(Icons.shield_outlined),
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v ?? '').trim().length < 2 ? 'Escribe el nombre' : null,
              ),
              const SizedBox(height: 20),

              Text(
                '¿Tienes los datos de sus jugadores?',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),

              _Opcion(
                seleccionada: _inventar,
                onTap: () => setState(() => _inventar = true),
                icono: Icons.auto_awesome,
                titulo: 'No los tengo',
                detalle:
                    'Arma un 11 con nombres inventados para poder jugar '
                    'igual. Quedan marcados como imaginarios y los puedes '
                    'corregir cuando consigas los datos reales.',
              ),
              const SizedBox(height: 10),
              _Opcion(
                seleccionada: !_inventar,
                onTap: () => setState(() => _inventar = false),
                icono: Icons.edit_note,
                titulo: 'Sí, los cargo yo',
                detalle:
                    'Crea el equipo vacío para que agregues sus '
                    'jugadores uno por uno.',
              ),

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
                      onPressed: () {
                        if (!_formulario.currentState!.validate()) return;
                        Navigator.pop(context, (
                          _nombre.text.trim(),
                          _inventar,
                        ));
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1B5E20),
                      ),
                      child: const Text('Crear'),
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

class _Opcion extends StatelessWidget {
  const _Opcion({
    required this.seleccionada,
    required this.onTap,
    required this.icono,
    required this.titulo,
    required this.detalle,
  });

  final bool seleccionada;
  final VoidCallback onTap;
  final IconData icono;
  final String titulo;
  final String detalle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: seleccionada
                ? const Color(0xFF1B5E20)
                : Colors.grey.shade300,
            width: seleccionada ? 2 : 1,
          ),
          color: seleccionada ? Colors.green.shade50 : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icono,
              color: seleccionada ? const Color(0xFF1B5E20) : Colors.grey,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    detalle,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
            if (seleccionada)
              const Icon(
                Icons.check_circle,
                color: Color(0xFF1B5E20),
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(
      texto.toUpperCase(),
      style: GoogleFonts.poppins(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.6,
        color: Colors.grey.shade600,
      ),
    ),
  );
}

/// Un equipo de la liga. Salen todos, tambien los incompletos: saber a
/// quien le faltan jugadores es parte de saber a quien se puede retar.
class _TarjetaEquipoLiga extends StatelessWidget {
  const _TarjetaEquipoLiga({required this.equipo, required this.onAbrir});

  final EquipoDelGrupo equipo;
  final VoidCallback onAbrir;

  @override
  Widget build(BuildContext context) {
    final completo = equipo.habilitado;
    final motivo = equipo.motivoNoRetable;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        onTap: onAbrir,
        leading: CircleAvatar(
          backgroundColor: completo
              ? const Color(0xFF1B5E20)
              : Colors.grey.shade400,
          foregroundColor: Colors.white,
          child: const Icon(Icons.shield),
        ),
        title: Text(
          equipo.name,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Icon(
                completo ? Icons.check_circle : Icons.error_outline,
                size: 14,
                color: completo
                    ? Colors.green.shade700
                    : Colors.orange.shade700,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  completo
                      ? '${equipo.jugadores} jugadores - listo para jugar'
                      : '${equipo.jugadores} jugadores - ${motivo ?? "incompleto"}',
                  style: TextStyle(
                    fontSize: 12,
                    color: completo
                        ? Colors.green.shade800
                        : Colors.orange.shade900,
                  ),
                ),
              ),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
