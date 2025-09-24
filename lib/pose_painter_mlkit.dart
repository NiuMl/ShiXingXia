import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:camera/camera.dart';

class PosePainterMlKit extends CustomPainter {
  final List<Map<String, dynamic>> points;
  final CameraLensDirection lensDir;

  PosePainterMlKit(this.points, this.lensDir);

  bool get isFront => lensDir == CameraLensDirection.front;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    /* mirror front camera canvas once */
    if (isFront) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }

    final dot = Paint()..color = Colors.red..strokeWidth = 3..style = PaintingStyle.fill;
    final line = Paint()..color = Colors.blue..strokeWidth = 2;

    /* draw with raw 0-1 coords scaled to preview pixels */
    for (final p in points) {
      if (p['confidence'] < .3) continue;
      final x = p['x'] * size.width;
      final y = p['y'] * size.height;
      canvas.drawCircle(Offset(x, y), 6, dot);
    }
    /* skeleton idem */
  }

  PoseLandmarkType _type(int i) => PoseLandmarkType.values[i];

  @override
  bool shouldRepaint(covariant PosePainterMlKit old) => old.points != points;
}