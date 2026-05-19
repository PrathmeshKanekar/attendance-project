import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'models/virtual_room_model.dart';
import 'room_capture_overlay.dart';

class RoomPreviewWidget extends StatelessWidget {
  final List<RoomCornerReading> corners;
  final double height;

  const RoomPreviewWidget({
    Key? key,
    required this.corners,
    this.height = 250.0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (corners.isEmpty) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.layers_clear_rounded,
                color: theme.disabledColor.withOpacity(0.5),
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                'No corners captured yet',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.textTheme.bodyMedium?.color?.withOpacity(0.5),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      height: height,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.primaryColor.withOpacity(0.2),
          width: 1.5,
        ),
      ),
      child: Stack(
        children: [
          // Centered grid effect
          Positioned.fill(
            child: CustomPaint(
              painter: _GridPainter(
                gridColor: isDark
                    ? Colors.white.withOpacity(0.03)
                    : Colors.black.withOpacity(0.02),
              ),
            ),
          ),
          // Canvas rendering the shape
          Positioned.fill(
            child: ClipRect(
              child: CustomPaint(
                painter: _RoomShapePainter(
                  corners: corners,
                  primaryColor: theme.primaryColor,
                  accentColor: theme.colorScheme.secondary,
                  isDark: isDark,
                ),
              ),
            ),
          ),
          // Bottom HUD info
          Positioned(
            left: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: (isDark ? const Color(0xFF1E293B) : Colors.white)
                    .withOpacity(0.9),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                  )
                ],
              ),
              child: Text(
                'Captured Corners: ${corners.length}/4',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.primaryColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  final Color gridColor;

  _GridPainter({required this.gridColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 1.0;

    const spacing = 20.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RoomShapePainter extends CustomPainter {
  final List<RoomCornerReading> corners;
  final Color primaryColor;
  final Color accentColor;
  final bool isDark;

  _RoomShapePainter({
    required this.corners,
    required this.primaryColor,
    required this.accentColor,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.isEmpty) return;

    // 1. Calculate boundaries (bounding box)
    double minLat = double.infinity;
    double maxLat = -double.infinity;
    double minLng = double.infinity;
    double maxLng = -double.infinity;

    for (final c in corners) {
      if (c.latitude < minLat) minLat = c.latitude;
      if (c.latitude > maxLat) maxLat = c.latitude;
      if (c.longitude < minLng) minLng = c.longitude;
      if (c.longitude > maxLng) maxLng = c.longitude;
    }

    // Handle single corner or identical corners division by zero
    double latSpan = maxLat - minLat;
    double lngSpan = maxLng - minLng;
    if (latSpan == 0) latSpan = 0.0001;
    if (lngSpan == 0) lngSpan = 0.0001;

    // 2. Compute normalized points fit to canvas with padding
    const padding = 32.0;
    final drawWidth = size.width - (padding * 2);
    final drawHeight = size.height - (padding * 2);

    List<Offset> points = [];
    for (final c in corners) {
      // Invert Y axis for screen representation (latitude is y, longitude is x)
      double normX = padding + ((c.longitude - minLng) / lngSpan) * drawWidth;
      double normY = padding + (1.0 - ((c.latitude - minLat) / latSpan)) * drawHeight;
      points.add(Offset(normX, normY));
    }

    // 3. Draw polygon fill & border
    final fillPaint = Paint()
      ..color = primaryColor.withOpacity(0.12)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = primaryColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    if (points.isNotEmpty) {
      path.moveTo(points[0].dx, points[0].dy);
      for (int i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      if (points.length == 4) {
        path.close();
      }
    }

    if (points.length > 1) {
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, borderPaint);
    }

    // 4. Draw markers at each corner
    final markerFillPaint = Paint()..color = isDark ? const Color(0xFF1E293B) : Colors.white;
    final markerBorderPaint = Paint()
      ..color = accentColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    for (int i = 0; i < points.length; i++) {
      final pt = points[i];
      // Draw outer circle glow
      canvas.drawCircle(pt, 10.0, Paint()..color = accentColor.withOpacity(0.3));
      canvas.drawCircle(pt, 7.0, markerFillPaint);
      canvas.drawCircle(pt, 7.0, markerBorderPaint);

      // Draw index number
      textPainter.text = TextSpan(
        text: '${i + 1}',
        style: TextStyle(
          color: accentColor,
          fontSize: 10.0,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(pt.dx - (textPainter.width / 2), pt.dy - (textPainter.height / 2)),
      );
    }

    // 5. Draw centroid center mark if exactly 4 corners
    if (points.length == 4) {
      double sumX = 0;
      double sumY = 0;
      for (final pt in points) {
        sumX += pt.dx;
        sumY += pt.dy;
      }
      final centerPt = Offset(sumX / 4, sumY / 4);
      final centerPaint = Paint()
        ..color = Colors.tealAccent.shade700
        ..style = PaintingStyle.fill;

      canvas.drawCircle(centerPt, 4.0, centerPaint);
      canvas.drawCircle(
        centerPt,
        8.0,
        Paint()
          ..color = Colors.tealAccent.shade700.withOpacity(0.2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RoomShapePainter oldDelegate) {
    return oldDelegate.corners.length != corners.length ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.isDark != isDark;
  }
}
