import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/session.dart';
import '../data/club_data_source.dart';
import '../models/models.dart';

/// El marcador del partido.
///
/// Tiene dos modos y decide solo cual usar:
///
///   * **En vivo** - hay un partido con estado `live` en la base. El
///     numero sale de `matches.team_score`, cantar un gol inserta un
///     evento y el marcador se actualiza en todos los dispositivos.
///   * **Local** - no hay backend o no hay partido en curso. Funciona
///     como el contador en memoria de la primera version de la app.
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

  StreamSubscription<FootballMatch?>? _suscripcion;
  bool _enviando = false;

  bool get _enVivo => _partido != null;
  int get _goles => _partido?.teamScore ?? _golesLocales;

  /// El contador local lo mueve cualquiera. Sobre un partido real hace
  /// falta rol de cuerpo tecnico: es la misma regla que aplica RLS en la
  /// base, adelantada a la interfaz para no ofrecer un boton que va a
  /// fallar.
  bool get _puedeAnotar {
    if (!_enVivo) return true;
    final s = widget.session;
    return s == null || s.puedeEditar;
  }

  @override
  void initState() {
    super.initState();
    _buscarPartidoEnVivo();
  }

  @override
  void dispose() {
    _suscripcion?.cancel();
    super.dispose();
  }

  /// Empieza en modo local y cambia a en vivo solo si encuentra partido.
  /// Asi no hay un spinner parpadeando en el arranque.
  Future<void> _buscarPartidoEnVivo() async {
    try {
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
      // Sin partido en vivo o sin red: se queda en modo local.
    }
  }

  Future<void> _anotarGol() async {
    if (!_enVivo) {
      setState(() => _golesLocales++);
      return;
    }

    if (!_puedeAnotar) {
      _avisar('Necesitas ser del cuerpo técnico del club para anotar goles.');
      return;
    }

    setState(() => _enviando = true);
    try {
      final actualizado = await widget.dataSource.logGoal(_partido!.id);
      if (mounted && actualizado != null) {
        setState(() => _partido = actualizado);
      }
    } catch (_) {
      _avisar('No se pudo registrar el gol. ¿Tienes permiso para editar este partido?');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _reiniciarMarcador() async {
    if (!_enVivo) {
      setState(() => _golesLocales = 0);
      return;
    }

    if (!_puedeAnotar) {
      _avisar('Necesitas ser del cuerpo técnico del club para reiniciar el marcador.');
      return;
    }

    // En vivo, reiniciar borra goles del historial: hay que preguntar.
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
              if (_enVivo) ...[
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
              color: const Color(0xFF1B5E20),
            ),
          ),
          Text(_enVivo ? 'En vivo' : 'Goles Anotados'),

          const SizedBox(height: 15),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: (_enviando || !_puedeAnotar) ? null : _anotarGol,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B5E20),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                ),
                icon: const Icon(Icons.sports_soccer, size: 20),
                label: Text(
                  '¡CANTAR GOL!',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              IconButton.filledTonal(
                onPressed: _puedeAnotar ? _reiniciarMarcador : null,
                icon: const Icon(Icons.refresh),
                tooltip: 'Reiniciar marcador',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.red.shade100,
                  foregroundColor: Colors.red.shade800,
                ),
              ),
            ],
          ),

          if (!_puedeAnotar) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Solo el cuerpo técnico puede anotar',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
