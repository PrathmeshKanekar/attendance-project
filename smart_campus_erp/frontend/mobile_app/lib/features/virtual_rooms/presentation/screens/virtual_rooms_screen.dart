// presentation/screens/virtual_rooms_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Displays college room listings with premium enterprise light theme elements.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/layout/app_layout.dart';
import '../../data/models/virtual_room_model.dart';
import '../providers/virtual_room_providers.dart';

class VirtualRoomsScreen extends ConsumerWidget {
  const VirtualRoomsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roomsAsync = ref.watch(virtualRoomsProvider);

    return AppLayout(
      title: 'Virtual Classrooms',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
          onPressed: () => ref.refresh(virtualRoomsProvider),
        ),
      ],
      fab: FloatingActionButton.extended(
        onPressed: () => context.push('/virtual-rooms/add'),
        icon: const Icon(Icons.add_location_alt_rounded, color: Colors.white),
        label: const Text('New Spatial Room', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.primary,
        elevation: 6,
      ),
      child: Container(
        color: AppColors.bgPrimary,
        child: roomsAsync.when(
          data: (rooms) {
            if (rooms.isEmpty) {
              return _buildEmptyState(context);
            }
            return RefreshIndicator(
              onRefresh: () async => ref.refresh(virtualRoomsProvider),
              color: AppColors.primary,
              backgroundColor: Colors.white,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                itemCount: rooms.length,
                itemBuilder: (context, index) {
                  final room = rooms[index];
                  return _RoomCard(room: room);
                },
              ),
            );
          },
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
          error: (err, stack) => _buildErrorState(err.toString(), ref),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.spatial_tracking_rounded, size: 80, color: AppColors.textSecondary.withOpacity(0.3)),
              const SizedBox(height: 24),
              const Text(
                'No Spatial Footprints Registered',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'High-accuracy 3D geofences prevent location spoofing. Register a room to get started.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () => context.push('/virtual-rooms/add'),
                icon: const Icon(Icons.add_location_alt_rounded, color: Colors.white),
                label: const Text('CREATE SPATIAL ROOM', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(String error, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 50, color: AppColors.danger),
            const SizedBox(height: 16),
            const Text('Failed to load classrooms', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(error, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => ref.refresh(virtualRoomsProvider),
              child: const Text('RETRY'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  final VirtualRoom room;
  const _RoomCard({required this.room});

  @override
  Widget build(BuildContext context) {
    final hasPolygon = room.hasPolygon;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderColor),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => context.push('/virtual-rooms/${room.id}'),
          child: Padding(
            padding: const EdgeInsets.all(18.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        room.name,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    _buildGeoFenceBadge(hasPolygon),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.business, size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      '${room.building} (Floor ${room.floorNumber})',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    const Spacer(),
                    const Icon(Icons.people_outline, size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      'Cap: ${room.capacity}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
                const Divider(height: 24, color: AppColors.borderColor),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      room.department.toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                    Row(
                      children: [
                        if (hasPolygon) ...[
                          IconButton(
                            icon: const Icon(Icons.spatial_audio_off_rounded, size: 18, color: AppColors.primary),
                            onPressed: () => context.push('/virtual-rooms/${room.id}/preview'),
                            tooltip: 'Preview Spatial Vector Frame',
                          ),
                          const SizedBox(width: 8),
                        ],
                        const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textSecondary),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGeoFenceBadge(bool hasPolygon) {
    final color = hasPolygon ? AppColors.success : AppColors.warning;
    final label = hasPolygon ? '3D POLYGON' : '2D RADIUS';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(hasPolygon ? Icons.polyline_rounded : Icons.radar_rounded, size: 10, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }
}
