import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/layout/app_layout.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/loading_widget.dart';
import '../../../../core/widgets/error_widget.dart';
import '../../../../core/widgets/empty_state_widget.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../models/virtual_room_model.dart';
import '../../providers/virtual_room_providers.dart';

class VirtualRoomsScreen extends ConsumerWidget {
  const VirtualRoomsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(virtualRoomsListProvider);
    final authState = ref.watch(authProvider);
    
    final isLabAssistant = authState is AuthSuccess && authState.user.role == 'lab_assistant';

    return AppLayout(
      title: 'Virtual Rooms',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: () {
            ref.read(virtualRoomsListProvider.notifier).loadRooms();
          },
          tooltip: 'Refresh',
        ),
      ],
      fab: isLabAssistant
          ? FloatingActionButton.extended(
              onPressed: () {
                context.push('/virtual-rooms/add');
              },
              icon: const Icon(Icons.add_location_alt_rounded),
              label: const Text('New Room'),
              backgroundColor: AppColors.primaryLight,
            )
          : null,
      child: listAsync.when(
        loading: () => const LoadingWidget(message: 'Loading virtual rooms...'),
        error: (e, _) => AppErrorWidget(
          message: 'Error: ${e.toString()}',
          onRetry: () {
            ref.read(virtualRoomsListProvider.notifier).loadRooms();
          },
        ),
        data: (rooms) {
          if (rooms.isEmpty) {
            return EmptyStateWidget(
              message: 'No Virtual Rooms',
              icon: Icons.room_preferences_rounded,
              subtitle: isLabAssistant
                  ? 'Tap the button below to capture and create your first geofenced virtual room.'
                  : 'No geofenced classrooms have been registered yet by lab assistants.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rooms.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final room = rooms[index];
              return _RoomCard(
                room: room,
                showActions: isLabAssistant,
                onTap: () {
                  context.push('/virtual-rooms/${room.id}');
                },
                onEdit: () {
                  context.push(
                    '/virtual-rooms/${room.id}/edit',
                    extra: room.toJson(),
                  );
                },
                onDelete: () {
                  _confirmDelete(context, ref, room);
                },
              );
            },
          );
        },
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, VirtualRoomModel room) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Virtual Room'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Text(
          'Are you sure you want to delete "${room.name}"? '
          'This will permanently remove the GPS boundaries and cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              minimumSize: const Size(90, 44),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref.read(virtualRoomsListProvider.notifier).deleteRoom(room.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Virtual Room deleted successfully.'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to delete room: $e'),
                      backgroundColor: AppColors.danger,
                    ),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  final VirtualRoomModel room;
  final bool showActions;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RoomCard({
    required this.room,
    required this.showActions,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Clean left room icon container
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: room.hasPolygon
                        ? AppColors.success.withOpacity(0.1)
                        : AppColors.textSecondary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    room.hasPolygon
                        ? Icons.map_rounded
                        : Icons.location_off_rounded,
                    color: room.hasPolygon ? AppColors.success : AppColors.textSecondary,
                    size: 26,
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
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${room.building} · Floor ${room.floorNumber}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Capacity: ${room.capacity} students · Dept: ${room.department}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Gorgeous status tags
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: room.hasPolygon
                                  ? AppColors.success.withOpacity(0.12)
                                  : AppColors.danger.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              room.hasPolygon ? '✓ GEOCONTAINED' : '⚠️ NO BOUNDARY',
                              style: TextStyle(
                                color: room.hasPolygon ? AppColors.success : AppColors.danger,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (room.hasPolygon)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.primaryLight.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                '4 Corners',
                                style: TextStyle(
                                  color: AppColors.primaryLight,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Edit/Delete actions list
                if (showActions)
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, color: AppColors.textSecondary, size: 20),
                        onPressed: onEdit,
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Edit Room',
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger, size: 20),
                        onPressed: onDelete,
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Delete Room',
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
}
