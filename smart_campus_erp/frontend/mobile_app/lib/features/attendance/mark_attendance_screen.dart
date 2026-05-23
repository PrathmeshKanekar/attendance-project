import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_campus_app/core/network/api_client.dart';
import 'package:smart_campus_app/core/services/location_service.dart';
import 'package:smart_campus_app/core/services/device_service.dart';
import 'package:smart_campus_app/features/face_scan/face_scan_params.dart';

enum LocStatus { idle, checking, inside, outside, error }

class LocationCheckState {
  final LocStatus status;
  final String? message;
  final double? distanceMeters;
  const LocationCheckState(this.status, {this.message, this.distanceMeters});
}

class SessionModel {
  final String id;
  final String subjectName;
  SessionModel({required this.id, required this.subjectName});
}

class MarkAttendanceScreen extends ConsumerStatefulWidget {
  final SessionModel session;
  const MarkAttendanceScreen({super.key, required this.session});

  @override
  ConsumerState<MarkAttendanceScreen> createState() => _MarkAttendanceScreenState();
}

class _MarkAttendanceScreenState extends ConsumerState<MarkAttendanceScreen> with SingleTickerProviderStateMixin {
  LocationCheckState _state = const LocationCheckState(LocStatus.idle);
  double _currentLat = 0.0;
  double _currentLng = 0.0;
  double _currentAlt = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkLocation());
  }

  Future<void> _checkLocation() async {
    setState(() => _state = const LocationCheckState(LocStatus.checking));
    try {
      final pos = await LocationService().getCurrentPosition();
      final api = ref.read(apiClientProvider);
      final res = await api.post('/api/attendance/check-location/', data: {
        'session_id': widget.session.id,
        'lat': pos.latitude,
        'lng': pos.longitude,
        'altitude': pos.altitude,
        'accuracy': pos.accuracy,
      });
      if (res.data['is_inside'] == true) {
        if (mounted) {
          setState(() {
            _state = const LocationCheckState(LocStatus.inside);
            _currentLat = pos.latitude;
            _currentLng = pos.longitude;
            _currentAlt = pos.altitude;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _state = LocationCheckState(
              LocStatus.outside,
              distanceMeters: (res.data['distance_meters'] as num?)?.toDouble() ?? 0.0,
            );
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _state = LocationCheckState(LocStatus.error, message: e.toString()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.session.subjectName} - Mark Attendance'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Step Progress Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                children: [
                  _buildStep(1, 'Location', _state.status == LocStatus.inside ? Colors.green : (_state.status == LocStatus.outside ? Colors.red : Colors.blue)),
                  _buildDivider(),
                  _buildStep(2, 'Face Scan', Colors.grey),
                  _buildDivider(),
                  _buildStep(3, 'Liveness', Colors.grey),
                  _buildDivider(),
                  _buildStep(4, 'Done', Colors.grey),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _buildBodyByState(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(int number, String title, Color color) {
    return Column(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: color,
          child: Text('$number', style: const TextStyle(color: Colors.white, fontSize: 11)),
        ),
        const SizedBox(height: 4),
        Text(title, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildDivider() {
    return Expanded(
      child: Container(
        height: 2,
        color: Colors.grey[300],
        margin: const EdgeInsets.only(bottom: 14),
      ),
    );
  }

  Widget _buildBodyByState() {
    switch (_state.status) {
      case LocStatus.idle:
      case LocStatus.checking:
        return const Column(
          key: ValueKey('checking'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.gps_fixed, color: Color(0xFF1E3A5F), size: 64),
            SizedBox(height: 16),
            Text('Checking your location...', style: TextStyle(color: Colors.grey)),
            SizedBox(height: 12),
            CircularProgressIndicator(),
          ],
        );
      case LocStatus.inside:
        return Column(
          key: const ValueKey('inside'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 100),
            const SizedBox(height: 16),
            Text('You are inside ${widget.session.subjectName} classroom', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F))),
            const Text('Distance from boundary: 0m', style: TextStyle(color: Colors.green, fontSize: 13)),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                onPressed: () async {
                  final deviceId = await DeviceService.getDeviceId();
                  if (mounted) {
                    context.push('/face-scan', extra: FaceScanParams(
                      sessionId: widget.session.id,
                      lat: _currentLat,
                      lng: _currentLng,
                      altitude: _currentAlt,
                      deviceId: deviceId,
                    ));
                  }
                },
                child: const Text('Mark Attendance →'),
              ),
            ),
          ],
        );
      case LocStatus.outside:
        final dist = _state.distanceMeters ?? 0.0;
        return Column(
          key: const ValueKey('outside'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_off, color: Colors.red, size: 64),
            const SizedBox(height: 16),
            Text('You are ${dist.toStringAsFixed(0)}m away', style: const TextStyle(color: Colors.red, fontSize: 18, fontWeight: FontWeight.bold)),
            const Text('Move closer to the classroom', style: TextStyle(color: Colors.grey, fontSize: 14)),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => _checkLocation(),
              child: const Text('Refresh Location'),
            ),
            const SizedBox(height: 16),
            const SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: null,
                child: Text('Mark Attendance'),
              ),
            ),
          ],
        );
      case LocStatus.error:
        return Column(
          key: const ValueKey('error'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.orange, size: 64),
            const SizedBox(height: 16),
            Text(_state.message ?? 'Unknown Error occurred', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _checkLocation(),
              child: const Text('Try Again'),
            ),
          ],
        );
    }
  }
}
