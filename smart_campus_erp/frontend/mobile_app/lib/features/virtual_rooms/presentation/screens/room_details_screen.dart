// presentation/screens/room_details_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Production room control panel in light theme.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/layout/app_layout.dart';
import '../providers/virtual_room_providers.dart';
import 'room_capture_screen.dart';
import 'live_room_validation_screen.dart';

class RoomDetailsScreen extends ConsumerWidget {
  final String roomId;
  const RoomDetailsScreen({super.key, required this.roomId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(roomDetailProvider(roomId));

    return AppLayout(
      title: 'Classroom Control Panel',
      actions: [
        IconButton(
          icon: const Icon(Icons.edit_location_alt_rounded, color: AppColors.primary),
          onPressed: () {
            detailAsync.whenData((room) {
              context.push('/admin/virtual-rooms/$roomId/edit', extra: room.toJson());
            });
          },
          tooltip: 'Edit Room Configuration',
        ),
      ],
      child: Container(
        color: AppColors.bgPrimary,
        child: detailAsync.when(
          data: (room) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildIdentityHeader(room),
                  const SizedBox(height: 24),
                  
                  _buildSectionHeader('SPATIAL TELEMETRY'),
                  _buildSpatialTelemetryCard(room),
                  const SizedBox(height: 24),

                  _buildSectionHeader('COORDINATE ANCHORS'),
                  _buildAnchorCard(room),
                  const SizedBox(height: 24),

                  _buildSectionHeader('ACTION MATRIX'),
                  _buildActionMatrix(context, ref, room),
                  const SizedBox(height: 40),
                ],
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

  Widget _buildIdentityHeader(dynamic room) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.borderColor),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.room_preferences_rounded, color: AppColors.primary, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  room.name,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  '${room.building} — Dept of ${room.department}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildSpatialTelemetryCard(dynamic room) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.borderColor),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          _telemetryRow('Validation Mode', room.hasPolygon ? '3D Spatial Polygon' : 'Legacy 2D Radius'),
          const Divider(color: AppColors.borderColor, height: 24),
          _telemetryRow('Captured Corners', '${room.cornerCount} / 4'),
          const Divider(color: AppColors.borderColor, height: 24),
          _telemetryRow('Dimensions', room.length != null ? '${room.length!.toStringAsFixed(1)}m × ${room.width!.toStringAsFixed(1)}m' : 'N/A'),
          const Divider(color: AppColors.borderColor, height: 24),
          _telemetryRow('Total Footprint Area', room.area != null ? '${room.area!.toStringAsFixed(1)} sq. meters' : 'N/A'),
          const Divider(color: AppColors.borderColor, height: 24),
          _telemetryRow('Floor Index', '${room.floorNumber}'),
        ],
      ),
    );
  }

  Widget _telemetryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildAnchorCard(dynamic room) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.borderColor),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          _telemetryRow('Center Latitude', room.centerLat?.toStringAsFixed(7) ?? 'N/A'),
          const Divider(color: AppColors.borderColor, height: 24),
          _telemetryRow('Center Longitude', room.centerLng?.toStringAsFixed(7) ?? 'N/A'),
          const Divider(color: AppColors.borderColor, height: 24),
          _telemetryRow('Altitudes (Min / Max)', room.minAltitude != null ? '${room.minAltitude!.round()}m — ${room.maxAltitude!.round()}m' : 'N/A'),
          const Divider(color: AppColors.borderColor, height: 24),
          _telemetryRow('Geofence Radius', '${room.radiusMeters.round()} meters'),
        ],
      ),
    );
  }

  Widget _buildActionMatrix(BuildContext context, WidgetRef ref, dynamic room) {
    final hasPolygon = room.hasPolygon;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _actionButton(
                icon: Icons.camera_outlined,
                label: hasPolygon ? 'Re-Capture Corners' : 'Capture Corners',
                color: AppColors.primary,
                onTap: () {
                  // Direct clean navigation to sequential capture screen
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => RoomCaptureScreen(roomId: roomId),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _actionButton(
                icon: Icons.spatial_audio_off_rounded,
                label: '3D Preview Frame',
                color: Colors.purple.shade700,
                onTap: hasPolygon 
                    ? () => context.push('/virtual-rooms/$roomId/preview') 
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _actionButton(
                icon: Icons.biotech_rounded,
                label: 'Test Live Validation',
                color: AppColors.success,
                onTap: () {
                  // Push to interactive coordinate verification screen
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => LiveRoomValidationScreen(roomId: roomId),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _actionButton(
                icon: Icons.restart_alt_rounded,
                label: 'Reset Geometry',
                color: Colors.amber.shade800,
                onTap: hasPolygon 
                    ? () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: const Text('Reset Spatial Footprint?'),
                            content: const Text('This will wipe all 4 captured corners and revert back to fallback legacy radius mode.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('CANCEL')),
                              TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('RESET', style: TextStyle(color: AppColors.danger))),
                            ],
                          ),
                        );
                        if (ok == true) {
                          await ref.read(roomCrudProvider.notifier).resetCorners(roomId);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Room boundaries reset successfully.')),
                          );
                        }
                      }
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger, size: 16),
            label: const Text('DEACTIVATE VIRTUAL CLASSROOM', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5)),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Deactivate classroom?'),
                  content: const Text('Are you sure you want to deactivate this classroom? Historical spatial attendance logs will remain, but students can no longer scan inside.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('CANCEL')),
                    TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('DEACTIVATE', style: TextStyle(color: AppColors.danger))),
                  ],
                ),
              );
              if (ok == true) {
                final success = await ref.read(roomCrudProvider.notifier).deleteRoom(roomId);
                if (success) {
                  context.pop();
                }
              }
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: AppColors.danger.withOpacity(0.04),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: AppColors.danger.withOpacity(0.1))),
            ),
          ),
        ),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    final disabled = onTap == null;
    final activeColor = disabled ? Colors.grey.shade400 : color;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
          decoration: BoxDecoration(
            color: disabled ? Colors.grey.shade100 : activeColor.withOpacity(0.06),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: disabled ? Colors.grey.shade200 : activeColor.withOpacity(0.18)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: activeColor, size: 24),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: disabled ? Colors.black26 : AppColors.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
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
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 50, color: AppColors.danger),
            const SizedBox(height: 16),
            const Text('Room Offline', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(error, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => ref.refresh(roomDetailProvider(roomId)),
              child: const Text('RETRY SYNC'),
            ),
          ],
        ),
      ),
    );
  }
}
