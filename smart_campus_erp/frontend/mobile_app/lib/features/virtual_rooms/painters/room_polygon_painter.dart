import 'package:flutter/material.dart';
import 'dart:ui' as ui;

class RoomPolygonPainter extends CustomPainter {
  final List<Offset> points;
  final Offset? userPos;

  RoomPolygonPainter({required this.points, this.userPos});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00F2FF)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(0, size.height),
        [const Color(0xFF00F2FF).withOpacity(0.2), Colors.transparent],
      )
      ..style = PaintingStyle.fill;

    // Draw Neon Grid
    final gridPaint = Paint()..color = Colors.white10..strokeWidth = 0.5;
    for (int i = 0; i < 10; i++) {
      canvas.drawLine(Offset(0, i * size.height / 10), Offset(size.width, i * size.height / 10), gridPaint);
      canvas.drawLine(Offset(i * size.width / 10, 0), Offset(i * size.width / 10, size.height), gridPaint);
    }

    if (points.length >= 3) {
      final path = Path()..addPolygon(points, true);
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, paint);
      
      // Draw Glow
      canvas.drawPath(path, Paint()
        ..color = const Color(0xFF00F2FF).withOpacity(0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6);

      // Draw Corners
      for (int i = 0; i < points.length; i++) {
        canvas.drawCircle(points[i], 5, Paint()..color = Colors.white);
        canvas.drawCircle(points[i], 3, Paint()..color = const Color(0xFF00F2FF));
      }
    }

    if (userPos != null) {
      canvas.drawCircle(userPos!, 8, Paint()..color = Colors.red.withOpacity(0.3)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      canvas.drawCircle(userPos!, 4, Paint()..color = Colors.red);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
