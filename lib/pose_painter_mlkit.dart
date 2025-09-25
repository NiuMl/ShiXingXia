import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
class PosePainterMlKit extends CustomPainter {
  final List<Map<String, dynamic>> points;
  final CameraLensDirection lensDir;
  final double imageWidth;
  final double imageHeight;

  static final Map<String, Offset> _smoothed = {};

  // Skeleton connections
  static const List<List<String>> _connections = [
    ['leftShoulder', 'leftElbow'],
    ['leftElbow', 'leftWrist'],
    ['rightShoulder', 'rightElbow'],
    ['rightElbow', 'rightWrist'],
    ['leftHip', 'leftKnee'],
    ['leftKnee', 'leftAnkle'],
    ['rightHip', 'rightKnee'],
    ['rightKnee', 'rightAnkle'],
    ['leftShoulder', 'rightShoulder'],
    ['leftHip', 'rightHip'],
    ['leftShoulder', 'leftHip'],
    ['rightShoulder', 'rightHip'],
    ['leftShoulder', 'nose'],
    ['rightShoulder', 'nose'],
  ];

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

    final bone = Paint()
      ..color = Colors.greenAccent.withOpacity(0.8)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    const double alpha = 0.6;

    // update smoothed positions
    for (final p in points) {
      if (p['confidence'] < .3) continue;

      dot.color = Colors.red.withOpacity(
          (p['confidence'] as double).clamp(0.3, 1.0));

      final x = (p['x'] / imageWidth) * size.width;
      final y = (p['y'] / imageHeight) * size.height;
      final newPos = Offset(x, y);

      final key = p['label'] as String;
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

    // draw skeleton
    for (final pair in _connections) {
      final p1 = _smoothed[pair[0]];
      final p2 = _smoothed[pair[1]];
      if (p1 != null && p2 != null) {
        canvas.drawLine(p1, p2, bone);
      }
    }
  }

  @override
  bool shouldRepaint(covariant PosePainterMlKit old) => true;
}
