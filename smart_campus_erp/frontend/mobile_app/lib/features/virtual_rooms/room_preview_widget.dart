import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'room_capture_overlay.dart';
import 'services/room_reconstruction_engine.dart';

class RoomPreviewWidget extends StatelessWidget {
  final List<RoomCornerReading> corners;
  final double height;

  const RoomPreviewWidget({
    Key? key,
    required this.corners,
    this.height = 280.0,
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
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.spatial_tracking_rounded,
                color: theme.disabledColor.withOpacity(0.4),
                size: 56,
              ),
              const SizedBox(height: 12),
              Text(
                'Awaiting Corner Captures',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.disabledColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Walk to corners and capture GPS + Sensor fusion data.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.disabledColor.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Attempt reconstruction to display metadata directly
    ReconstructedRoom? reconstructed;
    try {
      reconstructed = RoomReconstructionEngine.reconstruct(corners);
    } catch (e) {
      debugPrint('Reconstruction error: $e');
    }

    return Container(
      height: height,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.primaryColor.withOpacity(0.25),
          width: 1.5,
        ),
      ),
      child: Stack(
        children: [
          // 1. Grid Background
          Positioned.fill(
            child: CustomPaint(
              painter: _GridPainter(
                gridColor: isDark
                    ? Colors.white.withOpacity(0.04)
                    : Colors.black.withOpacity(0.03),
              ),
            ),
          ),
          
          // 2. Blueprint Canvas Painter
          Positioned.fill(
            child: ClipRect(
              child: CustomPaint(
                painter: _BlueprintPainter(
                  corners: corners,
                  reconstructed: reconstructed,
                  primaryColor: theme.primaryColor,
                  accentColor: theme.colorScheme.secondary,
                  isDark: isDark,
                ),
              ),
            ),
          ),

          // 3. Top HUD Dial (Quality & Compass Heading)
          if (reconstructed != null) ...[
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: (isDark ? const Color(0xFF1E293B) : Colors.white).withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Row(
                  children: [
                    // Heading Arrow Indicator
                    Transform.rotate(
                      angle: -reconstructed.orientationAngleDegrees * math.pi / 180.0,
                      child: const Icon(Icons.navigation_rounded, size: 14, color: Colors.redAccent),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${reconstructed.orientationAngleDegrees.toStringAsFixed(0)}° N',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: theme.primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // 4. Bottom HUD Info Card
          Positioned(
            left: 8,
            bottom: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: (isDark ? const Color(0xFF1E293B) : Colors.white).withOpacity(0.9),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                  )
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'SPATIAL AREA',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: theme.disabledColor,
                        ),
                      ),
                      Text(
                        reconstructed != null
                            ? '${reconstructed.areaSqMeters.toStringAsFixed(1)} m²'
                            : 'Pending (4 Corners)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: theme.primaryColor,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'PERIMETER',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: theme.disabledColor,
                        ),
                      ),
                      Text(
                        reconstructed != null
                            ? '${reconstructed.perimeter.toStringAsFixed(1)} meters'
                            : '${corners.length}/4 corners',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'QUALITY',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: theme.disabledColor,
                        ),
                      ),
                      Text(
                        reconstructed != null
                            ? '${reconstructed.qualityScore.toStringAsFixed(0)}%'
                            : 'CALIBRATING',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: reconstructed != null && reconstructed.qualityScore >= 80
                              ? Colors.tealAccent.shade400
                              : Colors.orangeAccent,
                        ),
                      ),
                    ],
                  ),
                ],
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

    const spacing = 18.0;
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

class _BlueprintPainter extends CustomPainter {
  final List<RoomCornerReading> corners;
  final ReconstructedRoom? reconstructed;
  final Color primaryColor;
  final Color accentColor;
  final bool isDark;

  _BlueprintPainter({
    required this.corners,
    required this.reconstructed,
    required this.primaryColor,
    required this.accentColor,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.isEmpty) return;

    // 1. Calculate bounding box of coordinates to fit and center the blueprint
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

    double latSpan = maxLat - minLat;
    double lngSpan = maxLng - minLng;
    if (latSpan == 0) latSpan = 0.0001;
    if (lngSpan == 0) lngSpan = 0.0001;

    // We add padding so the lines don't clip at the canvas edge
    const padding = 45.0;
    final drawWidth = size.width - (padding * 2);
    final drawHeight = size.height - (padding * 2) - 40; // Shift up to clear bottom HUD

    // 2. Normalize and project points
    List<Offset> screenPoints = [];
    final activeCornersList = reconstructed != null ? reconstructed!.orderedCorners : corners;

    for (final c in activeCornersList) {
      double normX = padding + ((c.longitude - minLng) / lngSpan) * drawWidth;
      double normY = padding + (1.0 - ((c.latitude - minLat) / latSpan)) * drawHeight;
      screenPoints.add(Offset(normX, normY));
    }

    // 3. Draw Polygon Wall fills
    final fillPaint = Paint()
      ..color = primaryColor.withOpacity(0.08)
      ..style = PaintingStyle.fill;

    final wallPaint = Paint()
      ..color = primaryColor
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    if (screenPoints.isNotEmpty) {
      path.moveTo(screenPoints[0].dx, screenPoints[0].dy);
      for (int i = 1; i < screenPoints.length; i++) {
        path.lineTo(screenPoints[i].dx, screenPoints[i].dy);
      }
      if (corners.length == 4) {
        path.close();
      }
    }

    if (screenPoints.length > 1) {
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, wallPaint);
    }

    // 4. Draw edge length labels in meters (only if reconstructed coordinates exist)
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    if (reconstructed != null && screenPoints.length == 4) {
      for (int i = 0; i < 4; i++) {
        final p1 = screenPoints[i];
        final p2 = screenPoints[(i + 1) % 4];
        final midPt = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
        
        final wallLen = reconstructed!.wallLengths[i];
        textPainter.text = TextSpan(
          text: '${wallLen.toStringAsFixed(1)}m',
          style: TextStyle(
            color: isDark ? Colors.tealAccent.shade400 : Colors.teal.shade800,
            fontSize: 9.5,
            fontWeight: FontWeight.bold,
            backgroundColor: (isDark ? const Color(0xFF0F172A) : Colors.white).withOpacity(0.8),
          ),
        );
        textPainter.layout();
        // Shift label slightly away from midpoint to prevent wall overlap
        canvas.drawCircle(midPt, 2.0, Paint()..color = Colors.tealAccent);
        textPainter.paint(
          canvas, 
          Offset(midPt.dx - (textPainter.width / 2), midPt.dy - (textPainter.height / 2) - 8),
        );
      }
    }

    // 5. Draw Centroid Mark
    if (screenPoints.length == 4) {
      double sumX = 0;
      double sumY = 0;
      for (final pt in screenPoints) {
        sumX += pt.dx;
        sumY += pt.dy;
      }
      final centerPt = Offset(sumX / 4, sumY / 4);
      final centerPaint = Paint()..color = Colors.tealAccent.shade700;

      canvas.drawCircle(centerPt, 4.0, centerPaint);
      canvas.drawCircle(
        centerPt,
        9.0,
        Paint()
          ..color = Colors.tealAccent.shade700.withOpacity(0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // 6. Draw Corner Markers with dynamic indices
    final markerFillPaint = Paint()..color = const Color(0xFF1E293B);
    final markerBorderPaint = Paint()
      ..color = accentColor
      ..strokeWidth = 2.0;

    for (int i = 0; i < screenPoints.length; i++) {
      final pt = screenPoints[i];
      canvas.drawCircle(
        pt,
        9.0,
        Paint()
          ..color = accentColor.withOpacity(0.25)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(pt, 6.0, markerFillPaint);
      canvas.drawCircle(pt, 6.0, markerBorderPaint..style = PaintingStyle.stroke);

      textPainter.text = TextSpan(
        text: '${i + 1}',
        style: TextStyle(
          color: accentColor,
          fontSize: 9.0,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(pt.dx - (textPainter.width / 2), pt.dy - (textPainter.height / 2)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BlueprintPainter oldDelegate) {
    return oldDelegate.corners.length != corners.length ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.isDark != isDark;
  }
}
