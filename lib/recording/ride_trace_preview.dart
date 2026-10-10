import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ride_session.dart';
import 'ride_store.dart';

/// Le petit tracé d'une sortie dans la liste « Mes sorties » : sa forme, en orange, sur la
/// même pastille sombre que l'aperçu d'un itinéraire (`RoutePreview`).
///
/// La forme se lit sur le disque de façon asynchrone ([RideStore.preview]) : la pastille
/// affiche d'abord le pictogramme, puis le tracé dès qu'il est prêt. Une sortie sans position
/// (GPS coupé, home-trainer) garde le pictogramme.
class RideTracePreview extends StatefulWidget {
  const RideTracePreview({super.key, required this.store, required this.session, this.size = 48});

  final RideStore store;
  final RideSession session;
  final double size;

  @override
  State<RideTracePreview> createState() => _RideTracePreviewState();
}

class _RideTracePreviewState extends State<RideTracePreview> {
  late Future<List<List<double>>> _trace;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(RideTracePreview old) {
    super.didUpdateWidget(old);
    // La sortie qui roule grandit : sa liste se reconstruit avec un résumé plus long, on relit.
    if (old.session.id != widget.session.id || old.session.pointCount != widget.session.pointCount) _load();
  }

  void _load() {
    _trace = widget.store.preview(widget.session.id, cache: widget.session.isFinished);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: const RadialGradient(
          center: Alignment(-0.4, -0.7),
          radius: 1.3,
          colors: [Color(0xFF5C666F), Color(0xFF4A545C), Color(0xFF3D464D)],
          stops: [0, 0.6, 1],
        ),
      ),
      child: FutureBuilder<List<List<double>>>(
        future: _trace,
        builder: (context, snapshot) {
          final trace = snapshot.data;
          if (trace == null || trace.length < 2) {
            return Icon(Icons.route, color: Colors.amber, size: widget.size * 0.5);
          }
          return CustomPaint(painter: _TracePainter(trace));
        },
      ),
    );
  }
}

class _TracePainter extends CustomPainter {
  _TracePainter(this.trace);

  final List<List<double>> trace;

  @override
  void paint(Canvas canvas, Size size) {
    // Projection plane : la longitude se raccourcit avec la latitude, sinon un tracé de nos
    // latitudes paraît étiré d'est en ouest.
    final meanLat = trace.map((p) => p[0]).reduce((a, b) => a + b) / trace.length;
    final lngScale = math.cos(meanLat * math.pi / 180);
    final xs = [for (final p in trace) p[1] * lngScale];
    final ys = [for (final p in trace) -p[0]];

    final minX = xs.reduce((a, b) => a < b ? a : b);
    final maxX = xs.reduce((a, b) => a > b ? a : b);
    final minY = ys.reduce((a, b) => a < b ? a : b);
    final maxY = ys.reduce((a, b) => a > b ? a : b);

    final padding = size.width * 0.12;
    final box = size.width - 2 * padding;
    final span = (maxX - minX) > (maxY - minY) ? (maxX - minX) : (maxY - minY);
    if (span <= 0) return;
    final scale = box / span;
    // Centré dans la pastille : un tracé tout en longueur ne colle pas au bord haut.
    final offsetX = padding + (box - (maxX - minX) * scale) / 2;
    final offsetY = padding + (box - (maxY - minY) * scale) / 2;

    final path = Path();
    for (var i = 0; i < trace.length; i++) {
      final x = offsetX + (xs[i] - minX) * scale;
      final y = offsetY + (ys[i] - minY) * scale;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.06
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = Colors.orange,
    );
  }

  @override
  bool shouldRepaint(_TracePainter old) => old.trace != trace;
}
