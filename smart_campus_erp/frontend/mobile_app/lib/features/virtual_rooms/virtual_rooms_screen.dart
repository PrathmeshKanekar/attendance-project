import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/layout/app_layout.dart';
import '../../core/widgets/empty_state_widget.dart';
import '../../core/widgets/error_widget.dart';
import '../../core/widgets/loading_widget.dart';
import 'virtual_room_providers.dart';

class VirtualRoomsScreen extends ConsumerStatefulWidget {
  const VirtualRoomsScreen({super.key});

  @override
  ConsumerState<VirtualRoomsScreen> createState() =>
      _VirtualRoomsScreenState();
}

class _VirtualRoomsScreenState extends ConsumerState<VirtualRoomsScreen> {
  String _search   = '';
  final String _building = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(virtualRoomsProvider);

    return AppLayout(
      title  : 'Virtual Rooms',
      actions: [
        IconButton(
          icon     : const Icon(Icons.refresh_rounded),
          onPressed: () => ref.invalidate(virtualRoomsProvider),
        ),
      ],
      fab: FloatingActionButton.extended(
        onPressed      : () => context.push('/admin/virtual-rooms/add'),
        icon           : const Icon(Icons.add_rounded),
        label          : const Text('Add Room'),
        backgroundColor: AppColors.primaryLight,
      ),
      child: async.when(
        loading: () => const LoadingWidget(message: 'Loading rooms...'),
        error  : (e, _) => AppErrorWidget(
          message: e.toString(),
          onRetry: () => ref.invalidate(virtualRoomsProvider),
        ),
        data   : (rooms) {
          // Apply local filters
          var filtered = rooms.where((r) {
            final matchSearch = _search.isEmpty
                || r['name'].toString().toLowerCase()
                    .contains(_search.toLowerCase());
            final matchBuilding = _building.isEmpty
                || (r['building']?.toString() ?? '').toLowerCase()
                    .contains(_building.toLowerCase());
            return matchSearch && matchBuilding;
          }).toList();

          // Group by building
          final Map<String, List<Map<String, dynamic>>> grouped = {};
          for (final r in filtered) {
            final building = r['building']?.toString().isEmpty == true
                ? 'No Building'
                : r['building']?.toString() ?? 'No Building';
            grouped.putIfAbsent(building, () => []).add(r);
          }

          return Column(
            children: [

              // ── Search bar ──────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child  : TextField(
                  decoration: const InputDecoration(
                    hintText  : 'Search rooms by name...',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),

              const SizedBox(height: 8),

              // ── Count bar ───────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child  : Row(
                  children: [
                    Text(
                      '${filtered.length} room${filtered.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                        color  : AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${grouped.keys.length} building${grouped.keys.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                        color  : AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // ── Rooms grouped by building ───────────────
              Expanded(
                child: filtered.isEmpty
                    ? const EmptyStateWidget(
                        message : 'No virtual rooms yet',
                        icon    : Icons.sensor_door_rounded,
                        subtitle: 'Tap + to add the first classroom',
                      )
                    : ListView(
                        padding : const EdgeInsets.fromLTRB(16, 0, 16, 80),
                        children: [
                          for (final entry in grouped.entries) ...[
                            // Building header
                            Padding(
                              padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
                              child  : Row(
                                children: [
                                  const Icon(
                                    Icons.business_rounded,
                                    size : 16,
                                    color: AppColors.textSecondary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    entry.key,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize  : 14,
                                      color     : AppColors.textSecondary,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color       : AppColors.bgSecondary,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '${entry.value.length}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color   : AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Rooms in this building
                            ...entry.value.map(
                              (room) => _RoomCard(
                                room    : room,
                                onTap   : () => context.push(
                                  '/admin/virtual-rooms/${room['id']}',
                                ),
                                onEdit  : () => context.push(
                                  '/admin/virtual-rooms/${room['id']}/edit',
                                  extra: room,
                                ),
                                onDelete: () =>
                                    _confirmDelete(context, ref, room),
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef    ref,
    Map<String, dynamic> room,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title  : const Text('Deactivate Room'),
        shape  : RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        content: Text(
          'Deactivate "${room['name']}"? '
          'Existing sessions will not be affected, '
          'but new sessions cannot use this room.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child    : const Text('Cancel'),
          ),
          ElevatedButton(
            style    : ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child    : const Text('Deactivate'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final success = await ref
        .read(roomCrudProvider.notifier)
        .deleteRoom(room['id'].toString());

    if (context.mounted) {
      final state = ref.read(roomCrudProvider);
      final msg   = state is RoomCrudSuccess
          ? state.message
          : state is RoomCrudError
              ? state.message
              : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content        : Text(msg),
          backgroundColor: success ? AppColors.success : AppColors.danger,
        ),
      );
      ref.read(roomCrudProvider.notifier).reset();
    }
  }
}


// ── Room card ──────────────────────────────────────────────
class _RoomCard extends StatelessWidget {
  final Map<String, dynamic> room;
  final VoidCallback         onTap;
  final VoidCallback         onEdit;
  final VoidCallback         onDelete;

  const _RoomCard({
    required this.room,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final sessionCount = room['session_count'] as int? ?? 0;
    final floor        = room['floor_number']  as int? ?? 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin    : const EdgeInsets.only(bottom: 10),
        padding   : const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color       : AppColors.cardBg,
          borderRadius: BorderRadius.circular(14),
          border      : Border.all(color: AppColors.borderColor),
        ),
        child: Row(
          children: [

            // Floor icon circle
            Container(
              width : 48, height: 48,
              decoration: BoxDecoration(
                color       : AppColors.primaryLight.withOpacity(0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.sensor_door_rounded,
                    color: AppColors.primaryLight,
                    size : 20,
                  ),
                  Text(
                    'F$floor',
                    style: const TextStyle(
                      color    : AppColors.primaryLight,
                      fontSize : 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name
                  Text(
                    room['name']?.toString() ?? '',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize  : 15,
                      color     : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Geo info
                  Text(
                    'Radius: ${room['radius_meters']}m  ·  '
                    'Alt: ${room['min_altitude']}–${room['max_altitude']}m',
                    style: const TextStyle(
                      color  : AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Chips row
                  Wrap(
                    spacing: 6,
                    children: [
                      _Chip(
                        label: '${room['radius_meters']}m radius',
                        color: AppColors.accent,
                      ),
                      _Chip(
                        label: '$sessionCount sessions',
                        color: AppColors.success,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Action buttons
            Column(
              children: [
                IconButton(
                  icon     : const Icon(
                    Icons.edit_rounded,
                    color: AppColors.textSecondary,
                    size : 20,
                  ),
                  onPressed: onEdit,
                  tooltip  : 'Edit',
                ),
                IconButton(
                  icon     : const Icon(
                    Icons.delete_outline_rounded,
                    color: AppColors.danger,
                    size : 20,
                  ),
                  onPressed: onDelete,
                  tooltip  : 'Deactivate',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label; final Color color;
  const _Chip({required this.label, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color       : color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: TextStyle(
        color: color, fontSize: 11, fontWeight: FontWeight.w600,
      )),
    );
  }
}
