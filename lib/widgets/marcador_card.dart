import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/session.dart';
import '../data/club_data_source.dart';
import '../models/models.dart';

const _verde = Color(0xFF1B5E20);

/// El marcador del partido, con su reloj.
///
/// Tiene dos modos y decide solo cual usar:
///
///   * **En vivo** - hay un partido en la base. El numero sale de
///     `matches.team_score`, cantar un gol inserta un evento y el
///     marcador se actualiza en todos los dispositivos.
///   * **Local** - no hay backend. Funciona como el contador en memoria
///     de la primera version de la app, que es la entrega academica.
///
/// El reloj importa mas de lo que parece: desde la migracion 45 la base
/// solo acepta goles y tarjetas con el partido en juego, asi que sin el
/// boton de empezar no habria forma de anotar nada.
class MarcadorCard extends StatefulWidget {
  const MarcadorCard({super.key, required this.dataSource, this.session});

  final ClubDataSource dataSource;

  /// Si es `null` no se comprueban permisos (modo local y pruebas).
  final Session? session;

  @override
  State<MarcadorCard> createState() => _MarcadorCardState();
}

class _MarcadorCardState extends State<MarcadorCard> {
  /// Contador en memoria del modo local.
  int _golesLocales = 0;

  /// Partido en curso. Si es null, estamos en modo local.
  FootballMatch? _partido;

  /// El mismo partido visto desde `partido_en_vivo`: trae la fase y el
  /// minuto, que es lo que decide qué botones tienen sentido.
  PartidoVivo? _reloj;

  StreamSubscription<FootballMatch?>? _suscripcion;
  Timer? _tictac;
  bool _enviando = false;

  bool get _enVivo => _partido != null;
  int get _goles => _partido?.teamScore ?? _golesLocales;

  /// El nombre del club, para no llamarlo "nosotros" en los desplegables.
  String get _miEquipo =>
      _reloj?.equipo ?? widget.session?.situacion.equipo ?? 'Mi equipo';

  String get _rival => _reloj?.rival ?? _partido?.opponentName ?? 'Rival';

  /// La sesión tiene permiso de edición. Es la misma regla que aplica
  /// RLS, adelantada a la interfaz para no ofrecer un botón que falla.
  bool get _puedeEditar {
    final s = widget.session;
    return s == null || s.puedeEditar;
  }

  /// Anotar exige, además, que el partido esté rodando: la base rechaza
  /// eventos sobre un partido programado o terminado.
  bool get _puedeAnotar {
    if (!_enVivo) return true; // modo local: el contador es de juguete
    return _puedeEditar && (_reloj?.enJuego ?? false);
  }

  bool get _puedeReiniciar => !_enVivo || _puedeEditar;

  @override
  void initState() {
    super.initState();
    _buscarPartidoEnVivo();
  }

  @override
  void dispose() {
    _suscripcion?.cancel();
    _tictac?.cancel();
    super.dispose();
  }

  /// Empieza en modo local y cambia a en vivo solo si encuentra partido.
  /// Asi no hay un spinner parpadeando en el arranque.
  Future<void> _buscarPartidoEnVivo() async {
    try {
      final reloj = await widget.dataSource.partidoDelDia();
      if (mounted && reloj != null) {
        setState(() => _reloj = reloj);
        _arrancarTictac();
      }

      final partido = await widget.dataSource.fetchLiveMatch();
      if (!mounted || partido == null) return;

      setState(() => _partido = partido);

      _suscripcion = widget.dataSource.watchMatch(partido.id).listen(
        (actualizado) {
          if (!mounted || actualizado == null) return;
          setState(() => _partido = actualizado);
        },
        onError: (_) {/* si se cae el tiempo real, el marcador se congela */},
      );
    } catch (_) {
      // Sin partido o sin red: se queda en modo local.
    }
  }

  /// El minuto lo calcula la base, no el teléfono: dos personas mirando
  /// el mismo partido tienen que ver el mismo minuto. Se relee cada 30 s.
  void _arrancarTictac() {
    _tictac?.cancel();
    _tictac = Timer.periodic(const Duration(seconds: 30), (_) => _releerReloj());
  }

  Future<void> _releerReloj() async {
    try {
      final reloj = await widget.dataSource.partidoDelDia();
      if (mounted) setState(() => _reloj = reloj);
    } catch (_) {
      // Un tic perdido no rompe nada: el siguiente lo recupera.
    }
  }

  Future<void> _mover(Future<void> Function() accion, String exito) async {
    setState(() => _enviando = true);
    try {
      await accion();
      await _releerReloj();
      final p = await widget.dataSource.fetchLiveMatch();
      if (mounted && p != null) setState(() => _partido = p);
      _avisar(exito);
    } catch (e) {
      _avisar(_enCristiano(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  String _enCristiano(Object e) {
    final m = e.toString().toLowerCase();
    if (m.contains('no está en juego') || m.contains('no esta en juego')) {
      return 'El partido no está en juego.';
    }
    if (m.contains('permiso') || m.contains('42501')) {
      return 'Esto lo hace el capitán o el cuerpo técnico.';
    }
    if (m.contains('todavía no') || m.contains('todavia no')) {
      return 'Todavía no es hora de empezar.';
    }
    return 'No se pudo. Inténtalo de nuevo.';
  }

  Future<void> _anotarGol() async {
    if (!_enVivo) {
      // Modo local: el contador de la primera version de la app. No
      // escribe en ningun lado, y por eso no pide autor ni equipo.
      setState(() => _golesLocales++);
      return;
    }

    if (!_puedeEditar) {
      _avisar('Necesitas ser del cuerpo técnico del club para anotar goles.');
      return;
    }
    if (!(_reloj?.enJuego ?? false)) {
      _avisar('Primero hay que empezar el partido.');
      return;
    }

    final datos = await _pedirDatosEvento(esGol: true);
    if (datos == null) return;

    setState(() => _enviando = true);
    try {
      final actualizado = await widget.dataSource.logGoal(
        _partido!.id,
        playerId: datos.playerId,
        rivalPlayerId: datos.rivalPlayerId,
        side: datos.side,
      );
      if (mounted && actualizado != null) {
        setState(() => _partido = actualizado);
      }
    } catch (e) {
      _avisar(_enCristiano(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _anotarTarjeta() async {
    if (!_puedeEditar || !(_reloj?.enJuego ?? false)) {
      _avisar('Las tarjetas se registran con el partido en juego.');
      return;
    }

    final datos = await _pedirDatosEvento(esGol: false);
    if (datos == null) return;

    setState(() => _enviando = true);
    try {
      await widget.dataSource.logCard(
        _partido!.id,
        type: datos.type,
        playerId: datos.playerId,
        rivalPlayerId: datos.rivalPlayerId,
        side: datos.side,
      );
      _avisar('Tarjeta registrada.');
    } catch (e) {
      _avisar(_enCristiano(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  /// Pregunta de quién fue el gol o la tarjeta.
  ///
  /// Los dos lados se eligen de una lista, no escribiendo un dorsal: el
  /// nombre es lo que se recuerda al final del partido, y así no hay
  /// forma de anotarle un gol a un número que no existe.
  Future<_DatosEvento?> _pedirDatosEvento({required bool esGol}) async {
    final nuestros = await widget.dataSource.fetchPlayers();
    final suyos = await widget.dataSource.fetchRivalPlayers(_partido!.id);
    if (!mounted) return null;

    var lado = TeamSide.us;
    var tipo = MatchEventType.yellowCard;
    Player? nuestro;
    RivalPlayer? suyo;

    return showDialog<_DatosEvento>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, redibujar) => AlertDialog(
          title: Text(esGol ? 'Registrar gol' : 'Registrar tarjeta'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!esGol)
                  DropdownButtonFormField<MatchEventType>(
                    initialValue: tipo,
                    decoration: const InputDecoration(labelText: 'Tipo'),
                    items: const [
                      DropdownMenuItem(
                        value: MatchEventType.yellowCard,
                        child: Text('Tarjeta amarilla'),
                      ),
                      DropdownMenuItem(
                        value: MatchEventType.redCard,
                        child: Text('Tarjeta roja'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) redibujar(() => tipo = v);
                    },
                  ),
                const SizedBox(height: 8),
                DropdownButtonFormField<TeamSide>(
                  initialValue: lado,
                  decoration: const InputDecoration(labelText: 'Equipo'),
                  items: [
                    // El nombre sale del partido, no escrito a mano: cada
                    // club tiene que ver el suyo.
                    DropdownMenuItem(
                      value: TeamSide.us,
                      child: Text(_miEquipo, overflow: TextOverflow.ellipsis),
                    ),
                    DropdownMenuItem(
                      value: TeamSide.them,
                      child: Text(_rival, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) redibujar(() => lado = v);
                  },
                ),
                const SizedBox(height: 8),
                if (lado == TeamSide.us)
                  DropdownButtonFormField<Player>(
                    initialValue: nuestro,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Jugador'),
                    items: [
                      for (final j in nuestros)
                        DropdownMenuItem(
                          value: j,
                          child: Text('${j.number ?? "-"}  ${j.fullName}',
                              overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => redibujar(() => nuestro = v),
                  )
                else if (suyos.isEmpty)
                  Text(
                    'No tienes cargada la plantilla del rival, así que el '
                    'gol queda sin autor.',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  )
                else
                  DropdownButtonFormField<RivalPlayer>(
                    initialValue: suyo,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Jugador'),
                    items: [
                      for (final j in suyos)
                        DropdownMenuItem(
                          value: j,
                          child: Text('${j.number ?? "-"}  ${j.fullName}',
                              overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => redibujar(() => suyo = v),
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
              onPressed: () => Navigator.pop(
                context,
                _DatosEvento(
                  playerId: lado == TeamSide.us ? nuestro?.id : null,
                  rivalPlayerId: lado == TeamSide.them ? suyo?.id : null,
                  side: lado,
                  type: esGol ? MatchEventType.goal : tipo,
                ),
              ),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reiniciarMarcador() async {
    if (!_enVivo) {
      setState(() => _golesLocales = 0);
      return;
    }

    if (!_puedeEditar) {
      _avisar('Necesitas ser del cuerpo técnico del club para anotar goles.');
      return;
    }

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Reiniciar el marcador?'),
        content: const Text(
          'Se borrarán todos los goles registrados en este partido. '
          'No se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Borrar goles'),
          ),
        ],
      ),
    );

    if (confirmado != true) return;

    try {
      await widget.dataSource.clearGoals(_partido!.id);
    } catch (_) {
      _avisar('No se pudo reiniciar el marcador.');
    }
  }

  void _avisar(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  @override
  Widget build(BuildContext context) {
    final r = _reloj;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.green.shade300, width: 2),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'MARCADOR DEL PARTIDO',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
              if (_enVivo && (r == null || r.enJuego)) ...[
                const SizedBox(width: 8),
                const _PuntoEnVivo(),
              ],
            ],
          ),

          if (_enVivo)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'vs ${_partido!.opponentName}',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
            ),

          const SizedBox(height: 10),

          Text(
            _enVivo ? _partido!.scoreLabel : '$_goles',
            style: GoogleFonts.bebasNeue(
              fontSize: 60,
              color: _verde,
            ),
          ),

          // La fase manda sobre el rotulo: "En vivo" con el partido en
          // descanso seria mentira.
          Text(r != null
              ? (r.enJuego && r.minuto != null
                  ? "${r.fase.label} · minuto ${r.minuto}"
                  : r.fase.label)
              : (_enVivo ? 'En vivo' : 'Goles Anotados')),

          if (r != null) ...[
            const SizedBox(height: 14),
            _ControlDelPartido(
              reloj: r,
              puede: _puedeEditar,
              ocupado: _enviando,
              onEmpezar: () => _mover(
                  () => widget.dataSource.iniciarPartido(r.id),
                  '¡Arrancó el partido!'),
              onDescanso: () => _mover(
                  () => widget.dataSource.irAlDescanso(r.id), 'Al descanso.'),
              onSegundoTiempo: () => _mover(
                  () => widget.dataSource.iniciarSegundoTiempo(r.id),
                  'Segundo tiempo.'),
              onTerminar: () => _mover(
                  () => widget.dataSource.finalizarPartido(r.id),
                  'Partido terminado.'),
            ),
          ],

          const SizedBox(height: 15),

          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: (_enviando || !_puedeAnotar) ? null : _anotarGol,
                icon: const Icon(Icons.sports_soccer),
                label: Text(
                  '¡CANTAR GOL!',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _verde,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 22, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
              ),
              if (_enVivo)
                OutlinedButton.icon(
                  onPressed:
                      (_enviando || !_puedeAnotar) ? null : _anotarTarjeta,
                  icon: const Icon(Icons.style_outlined),
                  label: const Text('Tarjeta'),
                ),
              IconButton.filledTonal(
                onPressed: _puedeReiniciar ? _reiniciarMarcador : null,
                icon: const Icon(Icons.refresh),
                tooltip: 'Reiniciar marcador',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.red.shade50,
                  foregroundColor: Colors.red.shade800,
                ),
              ),
            ],
          ),

          if (_enVivo && !_puedeEditar) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Solo el cuerpo técnico puede anotar',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Los botones del reloj. Cada fase ofrece exactamente el paso siguiente:
/// un partido no se puede "terminar" antes de empezar.
class _ControlDelPartido extends StatelessWidget {
  const _ControlDelPartido({
    required this.reloj,
    required this.puede,
    required this.ocupado,
    required this.onEmpezar,
    required this.onDescanso,
    required this.onSegundoTiempo,
    required this.onTerminar,
  });

  final PartidoVivo reloj;
  final bool puede;
  final bool ocupado;
  final VoidCallback onEmpezar;
  final VoidCallback onDescanso;
  final VoidCallback onSegundoTiempo;
  final VoidCallback onTerminar;

  @override
  Widget build(BuildContext context) {
    if (!puede) return const SizedBox.shrink();

    final (texto, icono, accion) = switch (reloj.fase) {
      FasePartido.listoParaEmpezar => ('Empezar partido', Icons.play_arrow, onEmpezar),
      FasePartido.primerTiempo => ('Ir al descanso', Icons.pause, onDescanso),
      FasePartido.descanso => ('Segundo tiempo', Icons.play_arrow, onSegundoTiempo),
      FasePartido.segundoTiempo => ('Terminar partido', Icons.stop, onTerminar),
      _ => (null, null, null),
    };

    if (texto == null) {
      // Esperando: decir cuándo, en vez de un botón que no hace nada.
      if (reloj.fase == FasePartido.esperando) {
        final h = reloj.kickoffAt;
        final hh = h.hour.toString().padLeft(2, '0');
        final mm = h.minute.toString().padLeft(2, '0');
        return Text(
          'Se podrá empezar 30 min antes: juega a las $hh:$mm',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        );
      }
      return const SizedBox.shrink();
    }

    return FilledButton.icon(
      onPressed: ocupado ? null : accion,
      icon: Icon(icono),
      label: Text(texto),
      style: FilledButton.styleFrom(
        backgroundColor: _verde,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    );
  }
}

class _DatosEvento {
  const _DatosEvento({
    required this.playerId,
    required this.rivalPlayerId,
    required this.side,
    required this.type,
  });

  final String? playerId;
  final String? rivalPlayerId;
  final TeamSide side;
  final MatchEventType type;
}

class _PuntoEnVivo extends StatelessWidget {
  const _PuntoEnVivo();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.red.shade600,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text(
        'EN VIVO',
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
