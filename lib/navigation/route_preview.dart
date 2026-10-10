import 'package:flutter/material.dart';

import 'route_summary.dart';

/// L'aperçu d'un itinéraire : son tracé coloré par la pente (montée en rouge, descente en
/// bleu, plat en gris) sur une pastille sombre — le même dessin que la liste des
/// itinéraires du site, à partir de ses `preview_segments`.
///
/// Sans aperçu (tracé trop court, site plus ancien que l'appli), la pastille garde le
/// pictogramme de l'activité : la ligne ne perd jamais son repère.
class RoutePreview extends StatelessWidget {
  const RoutePreview({
    super.key,
    required this.segments,
    required this.fallback,
    this.size = 48,
  });

  final List<RoutePreviewSegment> segments;
  final IconData fallback;
  final double size;

  /// Les mêmes teintes que `gradeColor` côté site : lisibles sur fond sombre.
  static Color colorOf(int category) => switch (category) {
        1 => const Color(0xFFE0503F),
        2 => const Color(0xFF2F8FED),
        _ => const Color(0xFF9AA0A6),
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: const RadialGradient(
          center: Alignment(-0.4, -0.7),
          radius: 1.3,
          colors: [Color(0xFF5C666F), Color(0xFF4A545C), Color(0xFF3D464D)],
          stops: [0, 0.6, 1],
        ),
      ),
      child: segments.isEmpty
          ? Icon(fallback, color: Colors.amber, size: size * 0.5)
          : CustomPaint(painter: _PreviewPainter(segments)),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.segments);

  final List<RoutePreviewSegment> segments;

  static final _number = RegExp(r'-?\d+(?:\.\d+)?');

  @override
  void paint(Canvas canvas, Size size) {
    // Le site dessine dans une boîte de 100 × 100 (trait de 6) : même proportion ici.
    final scale = size.width / 100;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6 * scale
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    for (final segment in segments) {
      final numbers = [
        for (final m in _number.allMatches(segment.path)) double.parse(m.group(0)!),
      ];
      if (numbers.length < 4) continue;
      final path = Path()..moveTo(numbers[0] * scale, numbers[1] * scale);
      for (var i = 2; i + 1 < numbers.length; i += 2) {
        path.lineTo(numbers[i] * scale, numbers[i + 1] * scale);
      }
      canvas.drawPath(path, stroke..color = RoutePreview.colorOf(segment.category));
    }
  }

  @override
  bool shouldRepaint(_PreviewPainter old) => old.segments != segments;
}
