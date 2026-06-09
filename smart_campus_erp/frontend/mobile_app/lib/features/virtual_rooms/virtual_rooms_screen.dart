import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/layout/app_layout.dart';
import 'providers/virtual_room_providers.dart';
import 'models/virtual_room_model.dart';

class VirtualRoomsScreen extends ConsumerStatefulWidget {
  const VirtualRoomsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<VirtualRoomsScreen> createState() => _VirtualRoomsScreenState();
}

class _VirtualRoomsScreenState extends ConsumerState<VirtualRoomsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(virtualRoomsProvider.notifier).fetchRooms();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Auth Role validation
    final authState = ref.watch(authProvider);
    final isLabAssistant = authState is AuthSuccess && authState.user.isLabAssistant;

    if (!isLabAssistant) {
      return Scaffold(
        appBar: AppBar(title: const Text('Access Denied')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.gpp_bad_rounded, size: 80, color: theme.colorScheme.error),
                const SizedBox(height: 16),
                Text(
                  'Unauthorized Role',
                  style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Only Lab Assistants are authorized to manage or capture virtual rooms.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.disabledColor),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final state = ref.watch(virtualRoomsProvider);
    final rooms = state.rooms.where((room) {
      final nameMatch = room.name.toLowerCase().contains(_searchQuery.toLowerCase());
      final buildingMatch = room.building.toLowerCase().contains(_searchQuery.toLowerCase());
      final deptMatch = room.department.toLowerCase().contains(_searchQuery.toLowerCase());
      return nameMatch || buildingMatch || deptMatch;
    }).toList();

    return AppLayout(
      title: 'Virtual Rooms',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: () => ref.read(virtualRoomsProvider.notifier).fetchRooms(),
        ),
      ],
      fab: FloatingActionButton.extended(
        onPressed: () => context.push('/admin/virtual-rooms/add'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Room'),
        elevation: 4,
      ),
      child: Column(
        children: [
          // Elegant Search and Header HUD
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'Search by room name, building, dept...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          
          if (state.isLoading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (state.error != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline_rounded, size: 60, color: theme.colorScheme.error),
                      const SizedBox(height: 16),
                      Text(
                        'Failed to load rooms',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        state.error!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.disabledColor),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => ref.read(virtualRoomsProvider.notifier).fetchRooms(),
                        child: const Text('Try Again'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (rooms.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.sensor_door_outlined, size: 80, color: theme.disabledColor.withOpacity(0.4)),
                    const SizedBox(height: 16),
                    Text(
                      _searchQuery.isEmpty ? 'No Virtual Rooms yet' : 'No rooms match your search',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, color: theme.disabledColor),
                    ),
                    const SizedBox(height: 8),
                    if (_searchQuery.isEmpty)
                      Text(
                        'Tap the "+" button below to build your first virtual room.',
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.disabledColor.withOpacity(0.7)),
                      ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: rooms.length,
                itemBuilder: (context, index) {
                  final room = rooms[index];
                  return _buildRoomCard(context, room, theme, isDark);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRoomCard(BuildContext context, VirtualRoomModel room, ThemeData theme, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => context.push('/admin/virtual-rooms/${room.id}'),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  // Status/Icon Lead
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: room.hasPolygon
                          ? Colors.teal.withOpacity(0.12)
                          : theme.primaryColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      room.hasPolygon ? Icons.polyline_rounded : Icons.sensor_door_rounded,
                      color: room.hasPolygon ? Colors.teal : theme.primaryColor,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Content Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          room.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${room.building} • Floor ${room.floorNumber} • Dept: ${room.department}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.people_rounded, size: 14, color: theme.disabledColor),
                            const SizedBox(width: 4),
                            Text(
                              'Capacity: ${room.capacity}',
                              style: theme.textTheme.labelMedium?.copyWith(color: theme.disabledColor),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: room.hasPolygon
                                    ? Colors.teal.withOpacity(0.08)
                                    : Colors.orange.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                room.hasPolygon ? 'GPS POLYGON MAPPED' : 'NO GPS MAPPED',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: room.hasPolygon ? Colors.teal : Colors.orange,
                                ),
                              ),
                            )
                          ],
                        )
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: theme.disabledColor.withOpacity(0.8),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
