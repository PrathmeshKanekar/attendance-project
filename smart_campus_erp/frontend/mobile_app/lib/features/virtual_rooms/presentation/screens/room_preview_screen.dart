import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/layout/app_layout.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/loading_widget.dart';
import '../../../../core/widgets/error_widget.dart';
import '../../models/virtual_room_model.dart';
import '../../repositories/virtual_room_repository.dart';
import 'room_detail_screen.dart';

final roomPreviewFetchProvider = FutureProvider.family<VirtualRoomModel, String>((ref, id) async {
  final repo = ref.read(virtualRoomRepositoryProvider);
  return repo.getVirtualRoom(id);
});

class RoomPreviewScreen extends ConsumerWidget {
  final String roomId;

  const RoomPreviewScreen({
    super.key,
    required this.roomId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // If roomId is empty, show a simple placeholder or load first room
    if (roomId.isEmpty) {
      return AppLayout(
        title: 'Geofence Preview',
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'Please select a virtual room from the list to preview its polygon footprint.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
          ),
        ),
      );
    }

    final previewAsync = ref.watch(roomPreviewFetchProvider(roomId));

    return AppLayout(
      title: 'Geofence Footprint',
      child: previewAsync.when(
        loading: () => const LoadingWidget(message: 'Generating footprint preview...'),
        error: (e, _) => AppErrorWidget(
          message: 'Error generating geofence: $e',
          onRetry: () {
            ref.invalidate(roomPreviewFetchProvider(roomId));
          },
        ),
        data: (room) {
          if (!room.hasPolygon) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.location_off_rounded, size: 64, color: AppColors.danger),
                    const SizedBox(height: 16),
                    Text(
                      'No Geofence Captured for ${room.name}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Please edit the room and capture exactly 4 corners using GPS before checking the geofence footprint.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${room.name} — Geofence Profile',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  'Building: ${room.building} · Floor: ${room.floorNumber} · Capacity: ${room.capacity}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 20),
                
                // Full screen relative canvas geofence visualizer
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.borderColor),
                    ),
                    child: Stack(
                      children: [
                        CustomPaint(
                          size: Size.infinite,
                          painter: _PreviewPainter(corners: room.corners),
                        ),
                        Positioned(
                          top: 16,
                          left: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.65),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.explore_rounded, color: AppColors.success, size: 14),
                                SizedBox(width: 6),
                                Text(
                                  'North Aligned Canvas',
                                  style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                
                // Quick diagnostic info
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.cardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.borderColor),
                  ),
                  child: Column(
                    children: [
                      _DiagnosticRow(label: 'Center Location', value: '${room.centerLat.toStringAsFixed(6)}, ${room.centerLng.toStringAsFixed(6)}'),
                      const Divider(height: 16),
                      const _DiagnosticRow(label: 'Validation Mode', value: 'GPS Polygon (Strict 2D)'),
                      const Divider(height: 16),
                      const _DiagnosticRow(label: 'Altitude Checks', value: 'Averaged relative floor validation'),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DiagnosticRow extends StatelessWidget {
  final String label;
  final String value;

  const _DiagnosticRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
        Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

// Full size custom painter to draw relative polygon footprint with diagonal indicators
class _PreviewPainter extends CustomPainter {
  final List<RoomCornerModel> corners;

  _PreviewPainter({required this.corners});

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length < 3) return;

    double minLat = corners.map((c) => c.latitude).reduce((a, b) => a < b ? a : b);
    double maxLat = corners.map((c) => c.latitude).reduce((a, b) => a > b ? a : b);
    double minLng = corners.map((c) => c.longitude).reduce((a, b) => a < b ? a : b);
    double maxLng = corners.map((c) => c.longitude).reduce((a, b) => a > b ? a : b);

    double latSpan = maxLat - minLat;
    double lngSpan = maxLng - minLng;

    if (latSpan == 0.0) latSpan = 0.0001;
    if (lngSpan == 0.0) lngSpan = 0.0001;

    const double padding = 60.0;
    final double drawW = size.width - (padding * 2);
    final double drawH = size.height - (padding * 2);

    final double maxSpan = latSpan > lngSpan ? latSpan : lngSpan;

    final List<Offset> points = corners.map((c) {
      double x = padding + (((c.longitude - minLng) / maxSpan) * drawW);
      double y = padding + (((maxLat - c.latitude) / maxSpan) * drawH);
      
      if (latSpan > lngSpan) {
        double offset = (drawW - ((lngSpan / maxSpan) * drawW)) / 2.0;
        x += offset;
      } else {
        double offset = (drawH - ((latSpan / maxSpan) * drawH)) / 2.0;
        y += offset;
      }
      return Offset(x, y);
    }).toList();

    // 1. Draw solid translucent filled polygon
    final fillPaint = Paint()
      ..color = AppColors.success.withOpacity(0.14)
      ..style = PaintingStyle.fill;

    final path = Path()..moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    path.close();
    canvas.drawPath(path, fillPaint);

    // 2. Draw diagonals inside polygon for structural visuals
    final diagonalPaint = Paint()
      ..color = AppColors.success.withOpacity(0.2)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(points[0], points[2], diagonalPaint);
    canvas.drawLine(points[1], points[3], diagonalPaint);

    // 3. Draw polygon outline
    final strokePaint = Paint()
      ..color = AppColors.success
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, strokePaint);

    // 4. Draw vertices (corners) and text labels
    final vertexPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      canvas.drawCircle(p, 9.0, Paint()..color = AppColors.success);
      canvas.drawCircle(p, 6.5, vertexPaint);
      
      final textSpan = TextSpan(
        text: 'C${i + 1}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9.0,
          fontWeight: FontWeight.bold,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      
      textPainter.paint(canvas, Offset(p.dx - (textPainter.width / 2), p.dy - (textPainter.height / 2)));
    }
  }

  @override
  bool shouldRepaint(covariant _PreviewPainter oldDelegate) {
    return oldDelegate.corners != corners;
  }
}
