import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:camera/camera.dart';

class PosePainterMlKit extends CustomPainter {
  final List<Map<String, dynamic>> points;
  final CameraLensDirection lensDir;
  final double imageWidth;
  final double imageHeight;

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

    for (final p in points) {
      if (p['confidence'] < .3) continue;

      // scale raw landmark coords → painted coords
      final x = (p['x'] / imageWidth) * size.width;
      final y = (p['y'] / imageHeight) * size.height;

      canvas.drawCircle(Offset(x, y), 6, dot);
    }
  }

  @override
  bool shouldRepaint(covariant PosePainterMlKit old) => old.points != points;
}
