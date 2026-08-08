import 'package:flutter/material.dart';
import 'dart:math' as math;

class TimeCircleWidget extends StatelessWidget {
  final int earnedMinutes;
  final int spentMinutes;

  const TimeCircleWidget({
    super.key,
    required this.earnedMinutes,
    required this.spentMinutes,
  });

  @override
  Widget build(BuildContext context) {
    final availableMinutes = earnedMinutes - spentMinutes;
    final progressRatio = earnedMinutes > 0 ? spentMinutes / earnedMinutes : 0.0;

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
                // Background circle
                SizedBox(
                  width: 220,
                  height: 220,
                  child: CustomPaint(
                    painter: _CirclePainter(
                      progress: progressRatio.clamp(0.0, 1.0),
                      earnedColor: Colors.green,
                      spentColor: Colors.orange,
                    ),
                  ),
                ),
                // Center content
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$availableMinutes',
                      style: const TextStyle(
                        fontSize: 64,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Text(
                      '可用\n分钟',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatItem(
                icon: Icons.fitness_center,
                label: '已获得',
                value: '$earnedMinutes 分钟',
                color: Colors.green,
              ),
              Container(
                width: 1,
                height: 40,
                color: Colors.white24,
              ),
              _StatItem(
                icon: Icons.phone_android,
                label: '已使用',
                value: '$spentMinutes 分钟',
                color: Colors.orange,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _CirclePainter extends CustomPainter {
  final double progress;
  final Color earnedColor;
  final Color spentColor;

  _CirclePainter({
    required this.progress,
    required this.earnedColor,
    required this.spentColor,
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

    // Earned circle (full circle in green)
    final earnedPaint = Paint()
      ..color = earnedColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius - strokeWidth / 2, earnedPaint);

    // Spent arc (orange, overlaying the green)
    if (progress > 0) {
      final spentPaint = Paint()
        ..color = spentColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      const startAngle = -math.pi / 2; // Start from top
      final sweepAngle = 2 * math.pi * progress;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
        startAngle,
        sweepAngle,
        false,
        spentPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_CirclePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
