import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/layout/app_layout.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/loading_widget.dart';
import '../../../../core/widgets/error_widget.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../models/virtual_room_model.dart';
import '../../repositories/virtual_room_repository.dart';
import 'add_edit_room_screen.dart';

final virtualRoomDetailProvider = FutureProvider.family<VirtualRoomModel, String>((ref, id) async {
  final repo = ref.read(virtualRoomRepositoryProvider);
  return repo.getVirtualRoom(id);
});

class RoomDetailScreen extends ConsumerWidget {
  final String roomId;

  const RoomDetailScreen({
    super.key,
    required this.roomId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(virtualRoomDetailProvider(roomId));
    final authState = ref.watch(authProvider);
    final isLabAssistant = authState is AuthSuccess && authState.user.role == 'lab_assistant';

    return AppLayout(
      title: 'Room Details',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: () {
            ref.invalidate(virtualRoomDetailProvider(roomId));
          },
          tooltip: 'Refresh',
        ),
      ],
      child: detailAsync.when(
        loading: () => const LoadingWidget(message: 'Fetching virtual room details...'),
        error: (e, _) => AppErrorWidget(
          message: 'Error loading room details: $e',
          onRetry: () {
            ref.invalidate(virtualRoomDetailProvider(roomId));
          },
        ),
        data: (room) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header block
                Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: room.hasPolygon
                            ? AppColors.success.withOpacity(0.12)
                            : AppColors.danger.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        room.hasPolygon ? Icons.map_rounded : Icons.location_off_rounded,
                        color: room.hasPolygon ? AppColors.success : AppColors.danger,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            room.name,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${room.building} · Floor ${room.floorNumber}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                
                // Metadata cards grid
                GridView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 2.2,
                  ),
                  children: [
                    _InfoCard(
                      label: 'Department',
                      value: room.department.isNotEmpty ? room.department : 'N/A',
                      icon: Icons.school_rounded,
                    ),
                    _InfoCard(
                      label: 'Capacity',
                      value: '${room.capacity} Students',
                      icon: Icons.people_alt_rounded,
                    ),
                    _InfoCard(
                      label: 'Center Latitude',
                      value: room.centerLat.toStringAsFixed(6),
                      icon: Icons.my_location_rounded,
                    ),
                    _InfoCard(
                      label: 'Center Longitude',
                      value: room.centerLng.toStringAsFixed(6),
                      icon: Icons.my_location_rounded,
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Footprint preview
                if (room.hasPolygon) ...[
                  const Text(
                    'POLYGON BOUNDARY FOOTPRINT',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 200,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.borderColor),
                    ),
                    child: Stack(
                      children: [
                        // Reuse the beautiful scale-normalized canvas custom painter
                        CustomPaint(
                          size: Size.infinite,
                          painter: _PolygonPreviewPainter(
                            corners: room.corners,
                          ),
                        ),
                        Positioned(
                          bottom: 12,
                          right: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Scale Normalized',
                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Corner coordinates list
                const Text(
                  'CAPTURED GEOLOCATION CORNERS',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                if (room.corners.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text(
                        'No physical corners captured for this virtual room.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                      ),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: room.corners.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, idx) {
                      final c = room.corners[idx];
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.cardBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.borderColor),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: AppColors.success.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '${c.cornerIndex}',
                                  style: const TextStyle(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Coordinate: ${c.latitude.toStringAsFixed(7)}, ${c.longitude.toStringAsFixed(7)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Altitude: ${c.altitude.toStringAsFixed(2)}m · Accuracy: ${c.accuracy.toStringAsFixed(1)}m',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                
                const SizedBox(height: 40),
                if (isLabAssistant)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryLight,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.edit_rounded, color: Colors.white),
                    label: const Text(
                      'Edit Coordinates',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    onPressed: () {
                      context.push(
                        '/virtual-rooms/${room.id}/edit',
                        extra: room.toJson(),
                      );
                    },
                  ),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _InfoCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primaryLight, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Canvas painter stub reused to support canvas previews in detail screen
class _PolygonPreviewPainter extends CustomPainter {
  final List<RoomCornerModel> corners;

  _PolygonPreviewPainter({required this.corners});

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

    const double padding = 30.0;
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

    final fillPaint = Paint()
      ..color = AppColors.success.withOpacity(0.12)
      ..style = PaintingStyle.fill;

    final path = Path()..moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    path.close();
    canvas.drawPath(path, fillPaint);

    final strokePaint = Paint()
      ..color = AppColors.success
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, strokePaint);

    final vertexPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      canvas.drawCircle(p, 7.0, Paint()..color = AppColors.success);
      canvas.drawCircle(p, 5.0, vertexPaint);
      
      final textSpan = TextSpan(
        text: 'C${i + 1}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 8.0,
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
  bool shouldRepaint(covariant _PolygonPreviewPainter oldDelegate) {
    return oldDelegate.corners != corners;
  }
}
