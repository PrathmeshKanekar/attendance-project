import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/constants/app_colors.dart';
import '../../core/widgets/loading_widget.dart';
import 'teacher_providers.dart';

class CreateSessionSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic>? preselectedAllocation;
  const CreateSessionSheet({super.key, this.preselectedAllocation});

  @override
  ConsumerState<CreateSessionSheet> createState() =>
      _CreateSessionSheetState();
}

class _CreateSessionSheetState extends ConsumerState<CreateSessionSheet> {
  final _formKey = GlobalKey<FormState>();

  Map<String, dynamic>? _selectedAllocation;
  Map<String, dynamic>? _selectedRoom;
  DateTime _startTime = DateTime.now();
  DateTime _endTime   = DateTime.now().add(const Duration(hours: 1));
  double   _radius    = 30.0;

  @override
  void initState() {
    super.initState();
    _selectedAllocation = widget.preselectedAllocation;
  }

  @override
  Widget build(BuildContext context) {
    final allocAsync  = ref.watch(myAllocationsProvider);
    final roomsAsync  = ref.watch(virtualRoomsProvider);
    final sessionState = ref.watch(createSessionProvider);
    final isLoading   = sessionState is CreateSessionLoading;

    return Container(
      decoration: const BoxDecoration(
        color       : Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        24, 16, 24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Form(
          key : _formKey,
          child: Column(
            mainAxisSize     : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // Handle
              Center(
                child: Container(
                  width : 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color       : AppColors.borderColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              const Text(
                'Start Attendance Session',
                style: TextStyle(
                  fontSize  : 20,
                  fontWeight: FontWeight.bold,
                  color     : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 20),

              // Subject dropdown
              const Text('Subject', style: TextStyle(
                fontWeight: FontWeight.w600, fontSize: 14,
                color     : AppColors.textPrimary,
              )),
              const SizedBox(height: 8),
              allocAsync.when(
                loading: () => const LoadingWidget(),
                error  : (e, _) => Text('Error: $e'),
                data   : (allocs) => DropdownButtonFormField<Map<String, dynamic>>(
                  value    : _selectedAllocation,
                  hint     : const Text('Select subject'),
                  isExpanded: true,
                  decoration: const InputDecoration(),
                  items    : allocs.map((a) => DropdownMenuItem(
                    value: a,
                    child: Text(
                      '${a['subject_name']} — Div ${a['division_name']}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  )).toList(),
                  onChanged: (v) => setState(() => _selectedAllocation = v),
                  validator: (v) => v == null ? 'Select a subject' : null,
                ),
              ),

              const SizedBox(height: 16),

              // Virtual room dropdown
              const Text('Virtual Room', style: TextStyle(
                fontWeight: FontWeight.w600, fontSize: 14,
                color     : AppColors.textPrimary,
              )),
              const SizedBox(height: 8),
              roomsAsync.when(
                loading: () => const LoadingWidget(),
                error  : (e, _) => Text('Error: $e'),
                data   : (rooms) => DropdownButtonFormField<Map<String, dynamic>>(
                  value    : _selectedRoom,
                  hint     : const Text('Select classroom'),
                  isExpanded: true,
                  decoration: const InputDecoration(),
                  items    : rooms.map((r) => DropdownMenuItem(
                    value: r,
                    child: Text(
                      '${r['name']} (${r['radius_meters']}m)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  )).toList(),
                  onChanged: (v) => setState(() => _selectedRoom = v),
                  validator: (v) => v == null ? 'Select a room' : null,
                ),
              ),

              const SizedBox(height: 16),

              // Time pickers
              Row(
                children: [
                  Expanded(child: _timePicker(
                    label  : 'Start Time',
                    time   : _startTime,
                    onPick : (t) => setState(() => _startTime = t),
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: _timePicker(
                    label  : 'End Time',
                    time   : _endTime,
                    onPick : (t) => setState(() => _endTime = t),
                  )),
                ],
              ),

              const SizedBox(height: 16),

              // Radius slider
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Geo Radius', style: TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 14,
                    color     : AppColors.textPrimary,
                  )),
                  Text('${_radius.round()}m',
                    style: const TextStyle(
                      color: AppColors.primaryLight,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Slider(
                value    : _radius,
                min      : 10,
                max      : 100,
                divisions: 18,
                label    : '${_radius.round()}m',
                activeColor: AppColors.primaryLight,
                onChanged: (v) => setState(() => _radius = v),
              ),

              const SizedBox(height: 20),

              // Submit button
              isLoading
                  ? const Center(child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation(AppColors.primaryLight),
                  ))
                  : ElevatedButton.icon(
                      onPressed: _submit,
                      icon     : const Icon(Icons.play_arrow_rounded),
                      label    : const Text('Start Session'),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _timePicker({
    required String   label,
    required DateTime time,
    required Function(DateTime) onPick,
  }) {
    return GestureDetector(
      onTap: () async {
        final picked = await showTimePicker(
          context    : context,
          initialTime: TimeOfDay.fromDateTime(time),
        );
        if (picked != null) {
          onPick(DateTime(
            time.year, time.month, time.day,
            picked.hour, picked.minute,
          ));
        }
      },
      child: Container(
        padding   : const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color       : AppColors.bgSecondary,
          borderRadius: BorderRadius.circular(12),
          border      : Border.all(color: AppColors.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(
              fontSize: 11, color: AppColors.textSecondary,
            )),
            const SizedBox(height: 4),
            Text(
              DateFormat('hh:mm a').format(time),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize  : 15,
                color     : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_endTime.isBefore(_startTime)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content        : Text('End time must be after start time.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    // ── CAPTURE TEACHER LIVE LOCATION ──
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    
    Position pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
      timeLimit: const Duration(seconds: 10),
    );

    await ref.read(createSessionProvider.notifier).createSession({
      'subject_allocation_id': _selectedAllocation!['id'],
      'virtual_room_id'      : _selectedRoom!['id'],
      'scheduled_start'      : _startTime.toIso8601String(),
      'scheduled_end'        : _endTime.toIso8601String(),
      'teacher_lat'          : pos.latitude,
      'teacher_lng'          : pos.longitude,
      'teacher_altitude'     : pos.altitude,
      'teacher_accuracy'     : pos.accuracy,
      'radius_meters'        : _radius,
    });

    if (!mounted) return;

    final state = ref.read(createSessionProvider);
    if (state is CreateSessionSuccess) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content        : Text(state.message),
          backgroundColor: AppColors.success,
        ),
      );
      ref.read(createSessionProvider.notifier).reset();
    } else if (state is CreateSessionError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content        : Text(state.message),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }
}
