import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/layout/app_layout.dart';
import 'providers/virtual_room_providers.dart';
import 'room_preview_widget.dart';

class RoomPreviewScreen extends ConsumerWidget {
  final String roomId;

  const RoomPreviewScreen({Key? key, required this.roomId}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final room = ref.watch(singleVirtualRoomProvider(roomId));

    if (room == null) {
      return AppLayout(
        title: 'Room Polygon Preview',
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.layers_clear_rounded, size: 60, color: theme.disabledColor),
              const SizedBox(height: 16),
              Text(
                'No room data found for preview',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => context.pop(),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    final centerLat = room.centerLat ?? 0.0;
    final centerLng = room.centerLng ?? 0.0;
    final width = (room.spatialMetadata['width_meters'] as num? ?? 10.0).toDouble();
    final length = (room.spatialMetadata['length_meters'] as num? ?? 12.0).toDouble();
    final rotation = (room.spatialMetadata['rotation_degrees'] as num? ?? room.orientationDegrees).toDouble();
    final confidence = (room.spatialMetadata['confidence_score'] as num? ?? room.reconstructionQuality).toDouble();

    return AppLayout(
      title: '${room.name} boundary shape',
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Centroid coordinates
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: theme.primaryColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.primaryColor.withOpacity(0.15)),
              ),
              child: Row(
                children: [
                  Icon(Icons.location_on_rounded, color: theme.primaryColor, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Averaged Center Point',
                          style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold, color: theme.primaryColor),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$centerLat, $centerLng',
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Canvas drawing (takes major space)
            Expanded(
              child: RoomPreviewWidget(
                centerLat: centerLat,
                centerLng: centerLng,
                widthMeters: width,
                lengthMeters: length,
                rotationDegrees: rotation,
                confidenceScore: confidence,
                interactive: false, // Static preview on this screen
                height: double.infinity,
              ),
            ),
            const SizedBox(height: 20),

            // Help info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? const Color(0xFF334155) : Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: theme.colorScheme.secondary, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'This map displays the real-world, high-precision rotated rectangle polygon boundary generated for this room.',
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Close button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => context.pop(),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('Close Preview', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
