// presentation/screens/live_room_validation_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Real-time spatial engine test playground.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/layout/app_layout.dart';
import '../../../../core/services/spatial_sensor_service.dart';
import '../providers/virtual_room_providers.dart';

class LiveRoomValidationScreen extends ConsumerStatefulWidget {
  final String roomId;
  const LiveRoomValidationScreen({super.key, required this.roomId});

  @override
  ConsumerState<LiveRoomValidationScreen> createState() => _LiveRoomValidationScreenState();
}

class _LiveRoomValidationScreenState extends ConsumerState<LiveRoomValidationScreen> {
  final _sensorService = SpatialSensorService();
  
  bool _isValidating = false;
  bool? _isInside;
  double? _localX;
  double? _localY;
  double? _localZ;
  double? _confidence;
  double? _distance;
  List<String> _spoofFlags = [];
  String _mode = 'Unknown';
  
  double _lat = 0.0;
  double _lng = 0.0;
  double _alt = 0.0;
  double _acc = 0.0;
  double _heading = 0.0;

  Timer? _validationTimer;

  @override
  void initState() {
    super.initState();
    _sensorService.startListening();
    _startLiveValidationLoop();
  }

  @override
  void dispose() {
    _validationTimer?.cancel();
    _sensorService.stopListening();
    super.dispose();
  }

  void _startLiveValidationLoop() {
    _validationTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted && !_isValidating) {
        _triggerValidation();
      }
    });
  }

  Future<void> _triggerValidation() async {
    setState(() => _isValidating = true);
    try {
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
      final sensorData = await _sensorService.captureCurrentState();

      if (!mounted) return;

      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _alt = pos.altitude;
        _acc = pos.accuracy;
        _heading = pos.heading;
      });

      final payload = {
        'lat': pos.latitude,
        'lng': pos.longitude,
        'altitude': pos.altitude,
        'gps_accuracy': pos.accuracy,
        if (sensorData != null) 'sensors': {
          'accelerometer': sensorData.accelerometer,
          'gyroscope': sensorData.gyroscope,
          'magnetic_field': sensorData.magneticField,
        },
      };

      final res = await ref.read(roomCrudProvider.notifier).checkLocation(
        roomId: widget.roomId,
        lat: pos.latitude,
        lng: pos.longitude,
        altitude: pos.altitude,
        gpsAccuracy: pos.accuracy,
        sensors: sensorData != null ? {
          'accelerometer': sensorData.accelerometer,
          'gyroscope': sensorData.gyroscope,
          'magnetic_field': sensorData.magneticField,
        } : null,
      );

      if (res != null && mounted) {
        setState(() {
          _isInside = res['is_valid'] == true;
          _localX = (res['local_x'] as num?)?.toDouble();
          _localY = (res['local_y'] as num?)?.toDouble();
          _localZ = (res['local_z'] as num?)?.toDouble();
          _confidence = (res['confidence'] as num?)?.toDouble() ?? 0.0;
          _distance = (res['distance_to_boundary'] as num?)?.toDouble();
          _spoofFlags = List<String>.from(res['spoof_flags'] ?? []);
          _mode = (res['validation_mode'] ?? 'radius').toString().toUpperCase();
        });
      }
    } catch (e) {
      print('Spatial validation error: $e');
    } finally {
      if (mounted) setState(() => _isValidating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title: 'Spatial Testing Console',
      actions: [
        IconButton(
          icon: const Icon(Icons.bolt_rounded, color: AppColors.primaryLight),
          onPressed: _triggerValidation,
          tooltip: 'Force Ping Spatial Engine',
        ),
      ],
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0F172A), Color(0xFF020617)],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildIntroPanel(),
              const SizedBox(height: 20),

              _buildSectionHeader('CONTAINMENT & STABILITY'),
              _buildStatusIndicator(),
              const SizedBox(height: 20),

              _buildSectionHeader('LOCAL ROOM AXES (ENU PROJECTION)'),
              _buildProjectionCard(),
              const SizedBox(height: 20),

              _buildSectionHeader('RAW GPS TELEMETRY'),
              _buildRawGpsCard(),
              const SizedBox(height: 20),

              _buildSectionHeader('ANTI-SPOOF FORENSICS'),
              _buildForensicsCard(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIntroPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primaryLight.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          const Icon(Icons.spatial_tracking_rounded, color: AppColors.primaryLight, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('GATEWAY DEPLOYMENT ACTIVE', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text('Pinging Spatial Validation Gateway every 3 seconds in mode: $_mode', style: const TextStyle(color: Colors.white38, fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        title,
        style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.5),
      ),
    );
  }

  Widget _buildStatusIndicator() {
    final hasStatus = _isInside != null;
    final inside = _isInside == true;
    final color = hasStatus ? (inside ? const Color(0xFF10B981) : AppColors.danger) : Colors.white24;
    final text = hasStatus ? (inside ? 'INSIDE BOUNDARY' : 'OUTSIDE BOUNDARY') : 'AWAITING LOCK';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: color.withOpacity(0.08), shape: BoxShape.circle),
            child: Icon(inside ? Icons.verified_rounded : Icons.gpp_bad_rounded, color: color, size: 36),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(
                  _distance != null && _distance! > 0.0
                      ? 'Distance outside: ${_distance!.toStringAsFixed(1)} meters'
                      : 'Containment Confidence: ${((_confidence ?? 0.0) * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectionCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _axisItem('LOCAL X', _localX != null ? '${_localX!.toStringAsFixed(2)}m' : 'Calculating', Colors.redAccent),
          _axisItem('LOCAL Y', _localY != null ? '${_localY!.toStringAsFixed(2)}m' : 'Calculating', Colors.greenAccent),
          _axisItem('LOCAL Z', _localZ != null ? '${_localZ!.toStringAsFixed(2)}m' : 'Calculating', Colors.blueAccent),
        ],
      ),
    );
  }

  Widget _axisItem(String label, String value, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(6)),
          child: Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildRawGpsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          _telemetryRow('Latitude', _lat.toStringAsFixed(7)),
          const Divider(color: Colors.white10, height: 20),
          _telemetryRow('Longitude', _lng.toStringAsFixed(7)),
          const Divider(color: Colors.white10, height: 20),
          _telemetryRow('Altitude / Accuracy', '${_alt.toStringAsFixed(1)}m (±${_acc.toStringAsFixed(1)}m)'),
          const Divider(color: Colors.white10, height: 20),
          _telemetryRow('Device Heading', '${_heading.toStringAsFixed(1)}°'),
        ],
      ),
    );
  }

  Widget _telemetryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildForensicsCard() {
    final clean = _spoofFlags.isEmpty;
    final color = clean ? const Color(0xFF10B981) : Colors.amberAccent;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Integrity Engine Status', style: TextStyle(color: Colors.white60, fontSize: 12)),
              Text(clean ? 'STABLE' : 'WARNINGS', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const Divider(color: Colors.white10, height: 24),
          if (clean)
            const Row(
              children: [
                Icon(Icons.shield_rounded, color: Color(0xFF10B981), size: 16),
                SizedBox(width: 8),
                Text('No simulated coordinates or fake GPS vectors detected.', style: TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            )
          else
            Column(
              children: _spoofFlags.map((flag) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.amberAccent, size: 16),
                    const SizedBox(width: 8),
                    Text(flag.toUpperCase().replaceAll('_', ' '), style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ),
              )).toList(),
            ),
        ],
      ),
    );
  }
}
