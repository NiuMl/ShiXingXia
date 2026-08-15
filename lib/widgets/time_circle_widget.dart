import 'package:flutter/material.dart';
import 'dart:math' as math;

class TimeCircleWidget extends StatelessWidget {
  /// 当天总运动分钟数
  final int totalMinutes;

  /// 每日目标分钟数（用于圆环进度比例），默认 60 分钟
  final int dailyGoalMinutes;

  const TimeCircleWidget({
    super.key,
    required this.totalMinutes,
    this.dailyGoalMinutes = 60,
  });

  @override
  Widget build(BuildContext context) {
    final progressRatio = dailyGoalMinutes > 0
        ? (totalMinutes / dailyGoalMinutes).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Circular progress indicator
          SizedBox(
            width: 220,
            height: 220,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Background + progress circle
                SizedBox(
                  width: 220,
                  height: 220,
                  child: CustomPaint(
                    painter: _CirclePainter(
                      progress: progressRatio,
                      progressColor: Colors.deepPurpleAccent,
                    ),
                  ),
                ),
                // Center content: 当天总分钟数
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$totalMinutes',
                      style: const TextStyle(
                        fontSize: 64,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Text(
                      '分钟',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        letterSpacing: 4,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CirclePainter extends CustomPainter {
  final double progress;
  final Color progressColor;

  _CirclePainter({
    required this.progress,
    required this.progressColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    const strokeWidth = 20.0;

    // Background circle (grey)
    final backgroundPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius - strokeWidth / 2, backgroundPaint);

    // Progress arc (gradient-like single color)
    if (progress > 0) {
      final progressPaint = Paint()
        ..color = progressColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      const startAngle = -math.pi / 2;
      final sweepAngle = 2 * math.pi * progress;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
        startAngle,
        sweepAngle,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_CirclePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.progressColor != progressColor;
  }
}
