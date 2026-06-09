import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/layout/app_layout.dart';
import 'providers/virtual_room_providers.dart';
import 'room_preview_widget.dart';
import 'room_capture_overlay.dart';
import 'models/virtual_room_model.dart';

class RoomDetailScreen extends ConsumerStatefulWidget {
  final String roomId;

  const RoomDetailScreen({Key? key, required this.roomId}) : super(key: key);

  @override
  ConsumerState<RoomDetailScreen> createState() => _RoomDetailScreenState();
}

class _RoomDetailScreenState extends ConsumerState<RoomDetailScreen> {
  bool _isDeleting = false;

  Future<void> _confirmDelete(BuildContext context, VirtualRoomModel room) async {
    final theme = Theme.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Virtual Room?'),
        content: Text('Are you sure you want to permanently delete "${room.name}"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      setState(() => _isDeleting = true);
      final success = await ref.read(virtualRoomsProvider.notifier).removeRoom(room.id);
      setState(() => _isDeleting = false);

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Virtual room deleted successfully.'),
              backgroundColor: Colors.teal,
            ),
          );
          context.pop();
        } else {
          final state = ref.read(virtualRoomsProvider);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.error ?? 'Failed to delete room.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Watch single room
    final room = ref.watch(singleVirtualRoomProvider(widget.roomId));

    if (room == null) {
      return AppLayout(
        title: 'Room Details',
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.warning_amber_rounded, size: 60, color: theme.disabledColor),
              const SizedBox(height: 16),
              Text(
                'Virtual room not found',
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

    // Adapt corners to RoomCornerReading
    final readings = room.corners.map((e) => RoomCornerReading(
      latitude: e.latitude,
      longitude: e.longitude,
      altitude: e.altitude,
      heading: e.heading,
      accuracy: e.accuracy,
    )).toList();

    return AppLayout(
      title: room.name,
      actions: [
        IconButton(
          icon: const Icon(Icons.edit_rounded),
          onPressed: () => context.push(
            '/admin/virtual-rooms/${room.id}/edit',
            extra: room.toJson(),
          ),
        ),
        IconButton(
          icon: _isDeleting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.delete_forever_rounded),
          color: theme.colorScheme.error,
          onPressed: _isDeleting ? null : () => _confirmDelete(context, room),
        ),
      ],
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Map View with Polygon
            Text(
              'Room Map View',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.primaryColor,
                letterSpacing: 0.5,
              ),
            ),
            RoomPreviewWidget(
              centerLat: room.centerLat ?? 0.0,
              centerLng: room.centerLng ?? 0.0,
              widthMeters: (room.spatialMetadata['width_meters'] as num? ?? 10.0).toDouble(),
              lengthMeters: (room.spatialMetadata['length_meters'] as num? ?? 12.0).toDouble(),
              rotationDegrees: (room.spatialMetadata['rotation_degrees'] as num? ?? room.orientationDegrees).toDouble(),
              confidenceScore: (room.spatialMetadata['confidence_score'] as num? ?? room.reconstructionQuality).toDouble(),
              interactive: false,
              height: 320,
            ),

            // Metadata card
            Text(
              'Room Metadata Info',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.primaryColor,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            _buildDetailCard(isDark, [
              _buildDetailRow(context, 'Building', room.building, Icons.apartment_rounded),
              const Divider(height: 24),
              _buildDetailRow(context, 'Floor Number', 'Floor ${room.floorNumber}', Icons.layers_rounded),
              const Divider(height: 24),
              _buildDetailRow(context, 'Department', room.department, Icons.work_rounded),
              const Divider(height: 24),
              _buildDetailRow(context, 'Max Capacity', '${room.capacity} Students', Icons.people_rounded),
              const Divider(height: 24),
              _buildDetailRow(context, 'Centroid (Center)', 
                room.centerLat != null && room.centerLng != null
                    ? '${room.centerLat!.toStringAsFixed(6)}, ${room.centerLng!.toStringAsFixed(6)}'
                    : 'Not calculated', 
                Icons.location_on_rounded),
              const Divider(height: 24),
              _buildDetailRow(context, 'Created By', room.createdByName, Icons.person_rounded),
            ]),
            const SizedBox(height: 28),

            // Captured corners detail
            Text(
              'GPS Boundary Coordinates',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.primaryColor,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: room.corners.length,
              itemBuilder: (context, idx) {
                final corner = room.corners[idx];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondary.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${corner.cornerIndex}',
                            style: TextStyle(
                              color: theme.colorScheme.secondary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Lat: ${corner.latitude.toStringAsFixed(7)}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                fontFamily: 'monospace',
                              ),
                            ),
                            Text(
                              'Lng: ${corner.longitude.toStringAsFixed(7)}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                fontFamily: 'monospace',
                              ),
                            ),
                            Text(
                              'Accuracy: ±${corner.accuracy.toStringAsFixed(1)}m • Altitude: ${corner.altitude.toStringAsFixed(1)}m',
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.disabledColor),
                            ),
                          ],
                        ),
                      )
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailCard(bool isDark, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value, IconData icon) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, color: theme.primaryColor.withOpacity(0.8), size: 22),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.disabledColor),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
