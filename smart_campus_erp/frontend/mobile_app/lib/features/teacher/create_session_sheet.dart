import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/constants/app_colors.dart';
import '../../core/widgets/loading_widget.dart';
import '../../utils/geofence_utils.dart';
import 'providers/teacher_providers.dart';

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
  bool     _isLocating = false;

  @override
  void initState() {
    super.initState();
    _selectedAllocation = widget.preselectedAllocation;
  }

  @override
  Widget build(BuildContext context) {
    final allocAsync  = ref.watch(teacherAllocationsProvider);
    final roomsAsync  = ref.watch(teacherRoomsProvider);
    final sessionState = ref.watch(createSessionProvider);
    
    // Combined loading state: either creating session or fetching GPS
    final bool isLoading = (sessionState is CreateSessionLoading) || _isLocating;

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

              // Subject
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

              // Room
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

              // Time
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

              // Radius
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
                max      : 150,
                divisions: 14,
                label    : '${_radius.round()}m',
                activeColor: AppColors.primaryLight,
                onChanged: (v) => setState(() => _radius = v),
              ),
              const SizedBox(height: 20),

              // Submit
              SizedBox(
                width: double.infinity,
                child: isLoading
                    ? const Center(child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation(AppColors.primaryLight),
                      ))
                    : ElevatedButton.icon(
                        onPressed: _submit,
                        icon     : const Icon(Icons.play_arrow_rounded),
                        label    : Text(_isLocating ? 'Fetching GPS...' : 'Start Session'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 50),
                        ),
                      ),
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

    setState(() => _isLocating = true);

    // Show loading overlay
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return WillPopScope(
          onWillPop: () async => false,
          child: Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(AppColors.primaryLight)),
                  SizedBox(width: 20),
                  Expanded(
                    child: Text(
                      'Acquiring GPS Position...',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    try {
      // Capture teacher live location
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          throw 'Location permission denied';
        }
      }
      
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 10),
        );
      } catch (_) {
        try {
          pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 5),
          );
        } catch (_) {
          pos = await Geolocator.getLastKnownPosition();
        }
      }

      // Pop the loading dialog/overlay
      if (mounted) {
        Navigator.pop(context);
      }

      if (pos == null) {
        throw 'Location acquisition timed out. Please ensure GPS is enabled and try again.';
      }

      // Check if accuracy is unstable (> 15m)
      if (pos.accuracy > 15.0) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('GPS Accuracy Error'),
              content: Text('Your GPS signal is unstable (accuracy: ${pos!.accuracy.toStringAsFixed(1)} meters). Please move closer to a window or an open area and try again. Maximum allowed accuracy is 15 meters.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return;
      }

      // Parse room coordinates and run isPointInsidePolygon check
      final roomPoly = parsePolygonFromRoom(_selectedRoom);
      if (roomPoly.isEmpty) {
        throw 'Classroom coordinates are not configured or are invalid.';
      }

      final teacherPt = LatLng(pos.latitude, pos.longitude);
      final isInside = isPointInsidePolygon(teacherPt, roomPoly);

      if (!isInside) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Out of Classroom Boundary'),
              content: const Text('You must be physically present inside the designated classroom area to start this attendance session. (Current position is outside room limits).'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return;
      }

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
        // CRITICAL: Refresh the dashboard list
        ref.invalidate(mySessionsProvider);
        
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
    } catch (e) {
      if (mounted && _isLocating) {
        // Make sure to pop the dialog if we throw an exception while it's showing
        Navigator.pop(context);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content        : Text('Location Error: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }
}
