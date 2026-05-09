import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_colors.dart';
import '../../core/layout/app_layout.dart';
import '../../core/widgets/error_widget.dart';
import '../../core/widgets/loading_widget.dart';
import 'virtual_room_providers.dart';

class RoomDetailScreen extends ConsumerStatefulWidget {
  final String roomId;
  const RoomDetailScreen({super.key, required this.roomId});

  @override
  ConsumerState<RoomDetailScreen> createState() => _RoomDetailScreenState();
}

class _RoomDetailScreenState extends ConsumerState<RoomDetailScreen> {
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();
  final _altCtrl = TextEditingController(text: '0.0');
  
  Map<String, dynamic>? _testResult;
  bool _isTesting = false;

  @override
  void dispose() {
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _altCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchCurrentLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition();
      setState(() {
        _latCtrl.text = pos.latitude.toStringAsFixed(7);
        _lngCtrl.text = pos.longitude.toStringAsFixed(7);
        _altCtrl.text = pos.altitude.toStringAsFixed(1);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  Future<void> _runTest() async {
    final lat = double.tryParse(_latCtrl.text);
    final lng = double.tryParse(_lngCtrl.text);
    final alt = double.tryParse(_altCtrl.text) ?? 0.0;

    if (lat == null || lng == null) return;

    setState(() => _isTesting = true);
    final result = await ref.read(roomCrudProvider.notifier).checkLocation(
      widget.roomId, lat, lng, alt,
    );
    setState(() {
      _testResult = result;
      _isTesting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final roomAsync = ref.watch(roomDetailProvider(widget.roomId));
    final statsAsync = ref.watch(roomStatsProvider(widget.roomId));

    return AppLayout(
      title: 'Room Details',
      child: roomAsync.when(
        loading: () => const LoadingWidget(message: 'Loading room details...'),
        error: (e, _) => AppErrorWidget(
          message: e.toString(),
          onRetry: () => ref.invalidate(roomDetailProvider(widget.roomId)),
        ),
        data: (room) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Section 1: Info Card ──────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: AppColors.cardBg,
                  border: Border(left: BorderSide(color: AppColors.primaryLight, width: 4)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.sensor_door_rounded, color: AppColors.primaryLight),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(room['name'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          Text('${room['building']} · Floor ${room['floor_number']}', 
                               style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                          if (room['created_by_name'] != null)
                            Text('Created by: ${room['created_by_name']}', 
                                 style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Section 2: Geo Details ────────────────────
              Row(
                children: [
                  Expanded(child: _GeoCard(
                    title: 'Location',
                    icon: Icons.place_rounded,
                    content: '${double.parse(room['center_lat'].toString()).toStringAsFixed(6)}\n${double.parse(room['center_lng'].toString()).toStringAsFixed(6)}',
                    onCopy: () => Clipboard.setData(ClipboardData(text: '${room['center_lat']}, ${room['center_lng']}')),
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: _GeoCard(
                    title: 'Boundary',
                    icon: Icons.radar_rounded,
                    content: '${room['radius_meters']}m radius\nAlt: ${room['min_altitude']}–${room['max_altitude']}m',
                  )),
                ],
              ),

              const SizedBox(height: 32),

              // ── Section 3: Test Location ──────────────────
              const Text('Test Geo Boundary', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.bgSecondary,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderColor),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: TextFormField(
                          controller: _latCtrl, 
                          decoration: const InputDecoration(labelText: 'Lat', isDense: true),
                          keyboardType: TextInputType.number,
                        )),
                        const SizedBox(width: 8),
                        Expanded(child: TextFormField(
                          controller: _lngCtrl, 
                          decoration: const InputDecoration(labelText: 'Lng', isDense: true),
                          keyboardType: TextInputType.number,
                        )),
                        const SizedBox(width: 8),
                        Expanded(child: TextFormField(
                          controller: _altCtrl, 
                          decoration: const InputDecoration(labelText: 'Alt', isDense: true),
                          keyboardType: TextInputType.number,
                        )),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: _fetchCurrentLocation,
                          icon: const Icon(Icons.my_location_rounded, size: 18),
                          label: const Text('Use My Location'),
                        ),
                        const Spacer(),
                        ElevatedButton(
                          onPressed: _isTesting ? null : _runTest,
                          child: _isTesting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Test'),
                        ),
                      ],
                    ),
                    if (_testResult != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (_testResult!['is_inside'] as bool) ? AppColors.success.withOpacity(0.1) : AppColors.danger.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: (_testResult!['is_inside'] as bool) ? AppColors.success : AppColors.danger),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (_testResult!['is_inside'] as bool) 
                                ? '✓ Inside boundary (${_testResult!['distance_from_center']}m from center)' 
                                : '✗ Outside boundary (${_testResult!['distance_to_boundary']}m to boundary)',
                              style: TextStyle(color: (_testResult!['is_inside'] as bool) ? AppColors.success : AppColors.danger, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              (_testResult!['altitude_ok'] as bool) ? '✓ Altitude OK' : '✗ Wrong floor / altitude',
                              style: TextStyle(color: (_testResult!['altitude_ok'] as bool) ? AppColors.success : AppColors.danger, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // ── Section 4: Usage Stats ───────────────────
              statsAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Error loading stats: $e'),
                data: (stats) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _StatChip(label: 'Total Sessions', value: stats['total_sessions'].toString(), color: AppColors.primaryLight),
                        const SizedBox(width: 8),
                        _StatChip(label: 'Active', value: stats['active_sessions'].toString(), color: AppColors.success, isActive: (stats['active_sessions'] as int) > 0),
                        const SizedBox(width: 8),
                        _StatChip(label: 'Avg Attendance', value: '${stats['avg_attendance_pct']}%', color: AppColors.accent),
                      ],
                    ),
                    const SizedBox(height: 32),
                    const Text('Recent Sessions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ...(stats['recent_sessions'] as List).map((s) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.cardBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.borderColor),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${s['subject_name']} (${s['session_code']})', style: const TextStyle(fontWeight: FontWeight.bold)),
                                Text('By ${s['teacher_name']} · ${DateFormat('dd MMM, hh:mm a').format(DateTime.parse(s['created_at']))}', 
                                     style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.bgSecondary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text('${s['present_count']}/${s['total_students']}', 
                                         style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    )),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              Row(
                children: [
                  Expanded(child: ElevatedButton.icon(
                    onPressed: () => context.push('/admin/virtual-rooms/${widget.roomId}/edit', extra: room),
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('Edit Room'),
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: OutlinedButton.icon(
                    onPressed: () async {
                      await _fetchCurrentLocation();
                      await _runTest();
                    },
                    icon: const Icon(Icons.location_searching_rounded),
                    label: const Text('Test My Location'),
                  )),
                ],
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _GeoCard extends StatelessWidget {
  final String title, content;
  final IconData icon;
  final VoidCallback? onCopy;
  const _GeoCard({required this.title, required this.content, required this.icon, this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(title, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
              if (onCopy != null) ...[
                const Spacer(),
                InkWell(onTap: onCopy, child: const Icon(Icons.copy_rounded, size: 14, color: AppColors.primaryLight)),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(content, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label, value;
  final Color color;
  final bool isActive;
  const _StatChip({required this.label, required this.value, required this.color, this.isActive = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isActive ? color.withOpacity(0.1) : AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isActive ? color : AppColors.borderColor),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isActive ? color : AppColors.textPrimary)),
          Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
