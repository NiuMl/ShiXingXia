import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

class PosePainterMlKit extends CustomPainter {
  final List<Map<String, dynamic>> points;
  final CameraLensDirection lensDir;
  final double imageWidth;
  final double imageHeight;

  // keep smoothed positions between frames
  static final Map<String, Offset> _smoothed = {};

  PosePainterMlKit(this.points, this.lensDir,
      {required this.imageWidth, required this.imageHeight});

  bool get isFront => lensDir == CameraLensDirection.front;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    if (isFront) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }

    final dot = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;

    const double alpha = 0.6; // smoothing factor [0..1], higher = snappier

    for (final p in points) {
      if (p['confidence'] < .3) continue;
      dot.color = Colors.red.withValues(
          alpha: (p['confidence'] as double).clamp(0.3, 1.0));

      // scale raw landmark coords → painted coords
      final x = (p['x'] / imageWidth) * size.width;
      final y = (p['y'] / imageHeight) * size.height;
      final newPos = Offset(x, y);

      final key = p['label'] as String;

      // blend with previous smoothed position
      final prev = _smoothed[key];
      final smoothed = (prev == null)
          ? newPos
          : Offset(
              prev.dx * (1 - alpha) + newPos.dx * alpha,
              prev.dy * (1 - alpha) + newPos.dy * alpha,
            );

      _smoothed[key] = smoothed;

      canvas.drawCircle(smoothed, 6, dot);
    }
  }

  @override
  bool shouldRepaint(covariant PosePainterMlKit old) => true;
}
