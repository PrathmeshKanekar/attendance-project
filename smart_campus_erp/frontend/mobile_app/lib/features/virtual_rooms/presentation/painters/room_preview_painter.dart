// presentation/painters/room_preview_painter.dart
// ─────────────────────────────────────────────────────────────────────────────
// Premium Light-Themed Custom Painter representing classroom boundary polygons in 2D/3D.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'dart:math' as math;

class RoomPreviewPainter extends CustomPainter {
  final List<Map<String, double>> corners;
  final Map<String, double>? userOffset; // X/Y metres offset relative to Origin
  final String headingAngle;
  final double length;
  final double width;
  final double area;

  RoomPreviewPainter({
    required this.corners,
    this.userOffset,
    required this.headingAngle,
    required this.length,
    required this.width,
    required this.area,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // ── 1. Clean Enterprise Light Grid Background ───────────────────────────
    final gridPaint = Paint()
      ..color = const Color(0xFFF1F5F9) // slate-100
      ..strokeWidth = 1.0;
    
    final int gridCount = 14;
    for (int i = 0; i <= gridCount; i++) {
      double x = i * size.width / gridCount;
      double y = i * size.height / gridCount;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (corners.isEmpty) {
      _drawNoDataText(canvas, size);
      return;
    }

    // ── 2. Scaler Mapping to Fit Canvas ─────────────────────────────────────
    final padding = 50.0;
    final drawW = size.width - (padding * 2);
    final drawH = size.height - (padding * 2);

    final xVals = corners.map((c) => c['x'] ?? 0.0).toList();
    final yVals = corners.map((c) => c['y'] ?? 0.0).toList();

    final minX = xVals.reduce(math.min);
    final maxX = xVals.reduce(math.max);
    final minY = yVals.reduce(math.min);
    final maxY = yVals.reduce(math.max);

    final rangeX = (maxX - minX).abs() < 0.1 ? 1.0 : (maxX - minX);
    final rangeY = (maxY - minY).abs() < 0.1 ? 1.0 : (maxY - minY);

    final scale = math.min(drawW / rangeX, drawH / rangeY);

    Offset toCanvas(double rx, double ry) {
      // Local X is horizontal, Local Y is vertical.
      // Origin at bottom-left in standard mathematical coordinates.
      double cx = padding + (rx - minX) * scale + (drawW - (maxX - minX) * scale) / 2;
      double cy = size.height - padding - (ry - minY) * scale - (drawH - (maxY - minY) * scale) / 2;
      return Offset(cx, cy);
    }

    final List<Offset> points = corners.map((c) => toCanvas(c['x'] ?? 0.0, c['y'] ?? 0.0)).toList();

    // ── 3. Render Fallback Circular Geo-fence ────────────────────────────────
    // Circular Geo-fence is centered in the middle of the room
    final centerLocalX = length / 2.0;
    final centerLocalY = width / 2.0;
    final centerCanvas = toCanvas(centerLocalX, centerLocalY);
    final fallbackRadius = math.max(length, width) * 0.7; // Radius calculated from dimensions
    final fallbackRadiusCanvas = fallbackRadius * scale;

    final fallbackFillPaint = Paint()
      ..color = const Color(0x0610B981) // emerald-500 very translucent
      ..style = PaintingStyle.fill;
    canvas.drawCircle(centerCanvas, fallbackRadiusCanvas, fallbackFillPaint);

    final fallbackBorderPaint = Paint()
      ..color = const Color(0xFF10B981).withOpacity(0.3) // emerald-500 translucent
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    
    // Draw dashed circle for fallback geo-fence
    const double dashWidth = 5.0;
    const double dashSpace = 4.0;
    double startAngle = 0.0;
    while (startAngle < 2 * math.pi) {
      canvas.drawArc(
        Rect.fromCircle(center: centerCanvas, radius: fallbackRadiusCanvas),
        startAngle,
        dashWidth / fallbackRadiusCanvas,
        false,
        fallbackBorderPaint,
      );
      startAngle += (dashWidth + dashSpace) / fallbackRadiusCanvas;
    }

    _drawText(
      canvas, 
      centerCanvas + Offset(-fallbackRadiusCanvas + 10, fallbackRadiusCanvas - 18), 
      'Circular Geo-fence (Backup)', 
      const Color(0xFF059669),
      fontSize: 9.0,
      fontWeight: FontWeight.w600,
    );

    // ── 4. Render Primary Room Polygon Boundary ──────────────────────────────
    final path = Path()..addPolygon(points, true);
    
    final fillPaint = Paint()
      ..color = const Color(0x183B82F6) // blue-500 soft translucent
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    final borderPaint = Paint()
      ..color = const Color(0xFF2563EB) // blue-600 elegant enterprise blue
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, borderPaint);

    // ── 5. Render Room Center crosshair/target ────────────────────────────────
    final centerCrossPaint = Paint()
      ..color = const Color(0xFFD97706) // amber-600
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(centerCanvas, 5, centerCrossPaint);
    canvas.drawLine(centerCanvas - const Offset(8, 0), centerCanvas + const Offset(8, 0), centerCrossPaint);
    canvas.drawLine(centerCanvas - const Offset(0, 8), centerCanvas + const Offset(0, 8), centerCrossPaint);
    _drawText(
      canvas, 
      centerCanvas + const Offset(10, -5), 
      'Room Center', 
      const Color(0xFFB45309), 
      fontSize: 9.0,
      fontWeight: FontWeight.bold,
    );

    // ── 6. Render X and Y Orthogonal Axes ──────────────────────────────────
    final originCanvas = toCanvas(0, 0);
    final xAxisCanvas = toCanvas(length, 0);
    final yAxisCanvas = toCanvas(0, width);

    final axisPaintX = Paint()
      ..color = const Color(0xFFDC2626) // crimson-600
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    
    final axisPaintY = Paint()
      ..color = const Color(0xFF16A34A) // emerald-600
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    // Draw axis lines
    canvas.drawLine(originCanvas, xAxisCanvas, axisPaintX);
    canvas.drawLine(originCanvas, yAxisCanvas, axisPaintY);

    // Draw Arrow heads
    _drawArrow(canvas, originCanvas, xAxisCanvas, const Color(0xFFDC2626));
    _drawArrow(canvas, originCanvas, yAxisCanvas, const Color(0xFF16A34A));

    // Axis Labels
    _drawText(canvas, xAxisCanvas + const Offset(5, -6), 'X Axis (Length)', const Color(0xFFB91C1C), fontWeight: FontWeight.bold);
    _drawText(canvas, yAxisCanvas + const Offset(-45, -15), 'Y Axis (Width)', const Color(0xFF15803D), fontWeight: FontWeight.bold);

    // ── 7. Render Z-Axis (Altitude) Vertical Indicator in Corner ─────────────
    _drawVerticalAltitudeIndicator(canvas, size);

    // ── 8. Render Compass Heading Arrow in Corner ────────────────────────────
    _drawCompassHeadingIndicator(canvas, size);

    // ── 9. Render Corner Dots and Coordinate Labels ─────────────────────────
    final dotPaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
    final dotOutline = Paint()
      ..color = const Color(0xFF1D4ED8) // blue-700
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < points.length; i++) {
      canvas.drawCircle(points[i], 6, dotPaint);
      canvas.drawCircle(points[i], 6, dotOutline);
      
      final label = 'C${i + 1} (${corners[i]['x']!.toStringAsFixed(1)}, ${corners[i]['y']!.toStringAsFixed(1)})';
      _drawText(
        canvas, 
        points[i] + const Offset(8, -16), 
        label, 
        const Color(0xFF334155), // slate-700
        fontSize: 10.0,
        fontWeight: FontWeight.bold,
      );
    }

    // ── 10. Render Student User Live Simulated Position ───────────────────────
    if (userOffset != null) {
      final ux = userOffset!['x']!;
      final uy = userOffset!['y']!;
      final uCanvas = toCanvas(ux, uy);

      final userGlow = Paint()
        ..color = const Color(0x40EC4899) // pink-500 soft glow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(uCanvas, 14, userGlow);

      final userOuter = Paint()
        ..color = const Color(0xFFDB2777) // pink-600
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(uCanvas, 8, userOuter);

      final userInner = Paint()
        ..color = const Color(0xFFDB2777) // pink-600
        ..style = PaintingStyle.fill;
      canvas.drawCircle(uCanvas, 4, userInner);

      _drawText(
        canvas, 
        uCanvas + const Offset(12, 4), 
        'Student (X: ${ux.toStringAsFixed(1)}m, Y: ${uy.toStringAsFixed(1)}m)', 
        const Color(0xFFBE185D), // pink-700
        fontSize: 10.0,
        fontWeight: FontWeight.w900,
      );
    }
  }

  void _drawVerticalAltitudeIndicator(Canvas canvas, Size size) {
    // Top-left Z-axis representation
    final startOffset = const Offset(20, 95);
    final indicatorHeight = 50.0;
    
    // Draw vertical Z scale line
    final zLinePaint = Paint()
      ..color = const Color(0xFF7C3AED) // purple-600
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    
    canvas.drawLine(startOffset, startOffset + Offset(0, indicatorHeight), zLinePaint);
    _drawArrow(canvas, startOffset + Offset(0, indicatorHeight), startOffset, const Color(0xFF7C3AED));

    // Tick lines for ceiling and floor
    canvas.drawLine(startOffset, startOffset + const Offset(6, 0), zLinePaint);
    canvas.drawLine(startOffset + Offset(0, indicatorHeight), startOffset + Offset(6, indicatorHeight), zLinePaint);

    _drawText(canvas, startOffset + const Offset(10, -5), 'Z Axis (Altitude Ceiling)', const Color(0xFF6D28D9), fontSize: 9.0, fontWeight: FontWeight.bold);
    _drawText(canvas, startOffset + const Offset(10, 15), 'Max Tol (+4.0m)', const Color(0xFF64748B), fontSize: 8.0);
    _drawText(canvas, startOffset + Offset(10, indicatorHeight - 5), 'Min Tol (-4.0m)', const Color(0xFF64748B), fontSize: 8.0);
  }

  void _drawCompassHeadingIndicator(Canvas canvas, Size size) {
    // Bottom-right orientation panel
    final double headDeg = double.tryParse(headingAngle) ?? 0.0;
    final center = Offset(size.width - 45, size.height - 45);
    final double radius = 22.0;

    final circlePaint = Paint()
      ..color = const Color(0xFFF1F5F9)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(center, radius, circlePaint);
    canvas.drawCircle(center, radius, borderPaint);

    // North label
    _drawText(canvas, center + const Offset(-3, -20), 'N', const Color(0xFF475569), fontSize: 8.0, fontWeight: FontWeight.bold);

    // Dynamic Heading Needle
    final angleRad = (headDeg - 90) * math.pi / 180.0;
    final needleEnd = center + Offset(math.cos(angleRad) * (radius - 4), math.sin(angleRad) * (radius - 4));
    final needlePaint = Paint()
      ..color = const Color(0xFF2563EB)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(center, needleEnd, needlePaint);
    canvas.drawCircle(center, 3, Paint()..color = const Color(0xFF1E3A8A));

    _drawText(
      canvas, 
      center + const Offset(-25, 24), 
      'Yaw: $headingAngle°', 
      const Color(0xFF1E293B), 
      fontSize: 9.0, 
      fontWeight: FontWeight.bold,
    );
  }

  void _drawArrow(Canvas canvas, Offset start, Offset end, Color color) {
    final dX = end.dx - start.dx;
    final dY = end.dy - start.dy;
    final angle = math.atan2(dY, dX);
    final double arrowSize = 8.0;

    final path = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(
        end.dx - arrowSize * math.cos(angle - math.pi / 6),
        end.dy - arrowSize * math.sin(angle - math.pi / 6),
      )
      ..lineTo(
        end.dx - arrowSize * math.cos(angle + math.pi / 6),
        end.dy - arrowSize * math.sin(angle + math.pi / 6),
      )
      ..close();

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, paint);
  }

  void _drawText(
    Canvas canvas, 
    Offset offset, 
    String text, 
    Color color, {
    double fontSize = 11.0,
    FontWeight fontWeight = FontWeight.normal,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color, 
          fontSize: fontSize, 
          fontWeight: fontWeight, 
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, offset);
  }

  void _drawNoDataText(Canvas canvas, Size size) {
    final tp = TextPainter(
      text: const TextSpan(
        text: 'NO POLYGON GEOMETRY REGISTERED',
        style: TextStyle(
          color: Color(0xFF94A3B8),
          fontSize: 13.0,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2));
  }

  @override
  bool shouldRepaint(covariant RoomPreviewPainter oldDelegate) {
    return oldDelegate.corners != corners || 
           oldDelegate.userOffset != userOffset || 
           oldDelegate.headingAngle != headingAngle;
  }
}
