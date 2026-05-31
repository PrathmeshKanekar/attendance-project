import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../teacher/providers/teacher_providers.dart';
import '../providers/session_repository_provider.dart';

class StartSessionSheet extends ConsumerStatefulWidget {
  const StartSessionSheet({super.key});

  @override
  ConsumerState<StartSessionSheet> createState() => _StartSessionSheetState();
}

class _StartSessionSheetState extends ConsumerState<StartSessionSheet> {
  final _formKey = GlobalKey<FormState>();
  Map<String, dynamic>? _selectedAllocation;
  Map<String, dynamic>? _selectedRoom;
  double _radius = 30.0;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final allocs = ref.watch(teacherAllocationsProvider);
    final rooms = ref.watch(teacherRoomsProvider);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(color: AppColors.borderColor, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const Text('Start New Session', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),

            // Allocation Dropdown
            allocs.when(
              data: (data) => DropdownButtonFormField<Map<String, dynamic>>(
                decoration: const InputDecoration(labelText: 'Select Subject'),
                items: data.map((a) => DropdownMenuItem(
                  value: a,
                  child: Text('${a['subject_name']} (${a['division_name']} - Y${a['division_year'] ?? a['year_of_study'] ?? ''})'),
                )).toList(),
                onChanged: (v) => setState(() => _selectedAllocation = v),
              ),
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const Text('Error loading subjects'),
            ),
            const SizedBox(height: 16),

            // Room Dropdown
            rooms.when(
              data: (data) => DropdownButtonFormField<Map<String, dynamic>>(
                decoration: const InputDecoration(labelText: 'Select Room'),
                items: data.map((r) => DropdownMenuItem(
                  value: r,
                  child: Text(r['name'] ?? ''),
                )).toList(),
                onChanged: (v) => setState(() => _selectedRoom = v),
              ),
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const Text('Error loading rooms'),
            ),
            const SizedBox(height: 16),

            // Radius Slider
            Text('Boundary Radius: ${_radius.round()}m', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            Slider(
              value: _radius,
              min: 10, max: 100,
              onChanged: (v) => setState(() => _radius = v),
              activeColor: AppColors.primaryLight,
            ),

            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isLoading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isLoading 
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('START SESSION', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_selectedAllocation == null || _selectedRoom == null) return;
    
    setState(() => _isLoading = true);
    try {
      // ── CAPTURE TEACHER LIVE LOCATION ──
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 8),
        );
      } catch (_) {
        try {
          pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 4),
          );
        } catch (_) {
          pos = await Geolocator.getLastKnownPosition();
        }
      }

      if (pos == null) {
        throw 'Location acquisition timed out. Please ensure GPS is enabled and try again.';
      }

      final now = DateTime.now();
      final start = now;
      final end = now.add(const Duration(hours: 1));

      final repository = ref.read(sessionRepositoryProvider);
      await repository.createSession({
        'subject_allocation_id': _selectedAllocation!['id'],
        'virtual_room_id'      : _selectedRoom!['id'],
        'scheduled_start'      : start.toIso8601String(),
        'scheduled_end'        : end.toIso8601String(),
        'teacher_lat'          : pos.latitude,
        'teacher_lng'          : pos.longitude,
        'teacher_altitude'     : pos.altitude,
        'teacher_accuracy'     : pos.accuracy,
        'radius_meters'        : _radius,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session started successfully!'), backgroundColor: AppColors.success),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
