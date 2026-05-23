/// Premium face guide overlay painter.
///
/// Draws a dynamic oval guide with:
/// - Color-coded state (red/yellow/green)
/// - Animated pulsing when aligned
/// - Corner bracket decorations for premium feel
/// - Semi-transparent darkened surround
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../models/face_alignment_state.dart';

class FaceOverlayPainter extends CustomPainter {
  final FaceAlignmentStatus alignmentStatus;
  final Color               overlayColor;
  final double              pulseValue; // 0.0 - 1.0 for pulsing animation
  final double              progressFraction; // 0.0 - 1.0 for liveness progress

  FaceOverlayPainter({
    required this.alignmentStatus,
    required this.overlayColor,
    this.pulseValue       = 0.0,
    this.progressFraction = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height * 0.42; // Slightly above center for natural selfie

    // Oval dimensions
    final ovalWidth  = size.width * 0.58;
    final ovalHeight = ovalWidth * 1.35; // Slightly taller than wide (face shape)

    // Apply subtle pulse when aligned
    final pulseScale = alignmentStatus == FaceAlignmentStatus.aligned
        ? 1.0 + (pulseValue * 0.015) // Very subtle 1.5% pulse
        : 1.0;

    final scaledWidth  = ovalWidth * pulseScale;
    final scaledHeight = ovalHeight * pulseScale;

    final ovalRect = Rect.fromCenter(
      center: Offset(centerX, centerY),
      width:  scaledWidth,
      height: scaledHeight,
    );

    // ── 1. Dark surround with oval cutout ──────────────────────────
    final surroundPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(ovalRect)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(
      surroundPath,
      Paint()..color = Colors.black.withOpacity(0.60),
    );

    // ── 2. Oval border with glow ───────────────────────────────────
    final borderPaint = Paint()
      ..color = overlayColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    // Outer glow
    final glowPaint = Paint()
      ..color = overlayColor.withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    canvas.drawOval(ovalRect, glowPaint);
    canvas.drawOval(ovalRect, borderPaint);

    // ── 3. Corner brackets for premium feel ────────────────────────
    _drawCornerBrackets(canvas, ovalRect, overlayColor);

    // ── 4. Progress arc (liveness progress ring) ───────────────────
    if (progressFraction > 0) {
      _drawProgressArc(canvas, ovalRect, progressFraction);
    }
  }

  void _drawCornerBrackets(Canvas canvas, Rect ovalRect, Color color) {
    const bracketLength = 18.0;
    const bracketOffset = 8.0;
    final paint = Paint()
      ..color = color.withOpacity(0.80)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    // Top-left
    final tl = Offset(ovalRect.left - bracketOffset, ovalRect.top - bracketOffset);
    canvas.drawLine(tl, tl + Offset(bracketLength, 0), paint);
    canvas.drawLine(tl, tl + Offset(0, bracketLength), paint);

    // Top-right
    final tr = Offset(ovalRect.right + bracketOffset, ovalRect.top - bracketOffset);
    canvas.drawLine(tr, tr + Offset(-bracketLength, 0), paint);
    canvas.drawLine(tr, tr + Offset(0, bracketLength), paint);

    // Bottom-left
    final bl = Offset(ovalRect.left - bracketOffset, ovalRect.bottom + bracketOffset);
    canvas.drawLine(bl, bl + Offset(bracketLength, 0), paint);
    canvas.drawLine(bl, bl + Offset(0, -bracketLength), paint);

    // Bottom-right
    final br = Offset(ovalRect.right + bracketOffset, ovalRect.bottom + bracketOffset);
    canvas.drawLine(br, br + Offset(-bracketLength, 0), paint);
    canvas.drawLine(br, br + Offset(0, -bracketLength), paint);
  }

  void _drawProgressArc(Canvas canvas, Rect ovalRect, double progress) {
    final arcRect = ovalRect.inflate(10);
    final arcPaint = Paint()
      ..color = const Color(0xFF22C55E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    // Draw from top center, clockwise
    canvas.drawArc(
      arcRect,
      -math.pi / 2, // Start at 12 o'clock
      2 * math.pi * progress,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant FaceOverlayPainter oldDelegate) {
    return oldDelegate.alignmentStatus != alignmentStatus ||
        oldDelegate.overlayColor != overlayColor ||
        oldDelegate.pulseValue != pulseValue ||
        oldDelegate.progressFraction != progressFraction;
  }
}
