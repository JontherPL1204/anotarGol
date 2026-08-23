import 'package:flutter/material.dart';

import '../models/models.dart';

/// La caja del proximo encuentro.
///
/// Antes era una linea de texto fija en `homescreen.dart`. Ahora recibe
/// el partido; si no hay ninguno programado, lo dice en vez de mentir.
class ProximoPartidoCard extends StatelessWidget {
  const ProximoPartidoCard({super.key, required this.partido});

  final FootballMatch? partido;

  @override
  Widget build(BuildContext context) {
    final p = partido;

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.shade600),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(p == null ? Icons.event_busy : Icons.event, color: Colors.amber.shade800),
          const SizedBox(width: 10),
          Expanded(
            child: p == null
                ? const Text(
                    'No hay partidos programados por ahora.',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Próximo encuentro: ${formatearFecha(p.kickoffAt)} '
                        '${p.isHome ? 'vs' : 'de visita ante'} ${p.opponentName}.',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      if (p.venue != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.place_outlined,
                                size: 14, color: Colors.brown.shade600),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                p.venue!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.brown.shade700,
                                ),
                              ),
                            ),
                          ],
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

const _dias = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo',
];

/// Formatea como "Domingo 24/08 16:00".
///
/// Se hace a mano en vez de agregar `intl`: es la unica fecha que muestra
/// la app y no justifica una dependencia mas.
String formatearFecha(DateTime fecha) {
  final dia = _dias[fecha.weekday - 1];
  final d = fecha.day.toString().padLeft(2, '0');
  final m = fecha.month.toString().padLeft(2, '0');
  final hh = fecha.hour.toString().padLeft(2, '0');
  final mm = fecha.minute.toString().padLeft(2, '0');
  return '$dia $d/$m $hh:$mm';
}
