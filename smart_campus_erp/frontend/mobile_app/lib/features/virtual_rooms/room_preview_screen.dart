import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'providers/virtual_room_providers.dart';
import 'room_preview_widget.dart';
import 'room_capture_overlay.dart';
import 'models/virtual_room_model.dart';

class RoomPreviewScreen extends ConsumerWidget {
  final String roomId;

  const RoomPreviewScreen({Key? key, required this.roomId}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final room = ref.watch(singleVirtualRoomProvider(roomId));

    if (room == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Room Polygon Preview')),
        body: Center(
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

    final readings = room.corners.map((e) => RoomCornerReading(
      latitude: e.latitude,
      longitude: e.longitude,
      altitude: e.altitude,
      heading: e.heading,
      accuracy: e.accuracy,
    )).toList();

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B0F19) : Colors.grey.shade50,
      appBar: AppBar(
        title: Text('${room.name} boundary shape'),
      ),
      body: Padding(
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
                          room.centerLat != null && room.centerLng != null
                              ? '${room.centerLat!.toStringAsFixed(7)}, ${room.centerLng!.toStringAsFixed(7)}'
                              : 'Not Calculated',
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
                corners: readings,
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
                      'This 2D canvas displays the real boundary polygon captured for this room. Corners are sorted by sequence index.',
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
