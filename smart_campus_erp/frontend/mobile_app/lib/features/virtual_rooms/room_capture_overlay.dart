// room_capture_overlay.dart
// ─────────────────────────────────────────────────────────────────────────────
// Full-screen camera overlay for capturing 4 physical room corners.
// Reads GPS + compass + accelerometer + gyroscope + magnetometer simultaneously.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../core/constants/app_colors.dart';
import 'models/corner_data.dart';

class RoomCaptureOverlay extends StatefulWidget {
  final Function(List<CornerData>) onCaptureComplete;

  const RoomCaptureOverlay({super.key, required this.onCaptureComplete});

  @override
  State<RoomCaptureOverlay> createState() => _RoomCaptureOverlayState();
}

class _RoomCaptureOverlayState extends State<RoomCaptureOverlay>
    with SingleTickerProviderStateMixin {
  // ── Camera ────────────────────────────────────────────────────────────────
  CameraController? _camera;
  bool _cameraInitialized = false;

  // ── Sensor streams ────────────────────────────────────────────────────────
  StreamSubscription<Position>?      _gpsSub;
  StreamSubscription<CompassEvent>?  _compassSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>?     _gyroSub;
  StreamSubscription<MagnetometerEvent>?  _magSub;

  // ── Live sensor values ────────────────────────────────────────────────────
  Position? _pos;
  double    _heading    = 0.0;
  double    _accelX     = 0.0, _accelY = 0.0, _accelZ = 9.81;
  double    _gyroX      = 0.0, _gyroY  = 0.0, _gyroZ  = 0.0;
  double    _magX       = 0.0, _magY   = 0.0, _magZ   = 0.0;
  double?   _baroPressure;

  // ── Capture state ─────────────────────────────────────────────────────────
  final List<CornerData> _captured   = [];
  int                    _step       = 0;   // 0..3
  bool                   _capturing  = false;
  String?                _captureErr;
  String?                _initError;

  // ── UI ────────────────────────────────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulse;

  static const _labels = ['Corner A', 'Corner B', 'Corner C', 'Corner D'];
  static const _hints  = [
    'Stand at the FRONT-LEFT corner of the classroom.',
    'Walk to the FRONT-RIGHT corner.',
    'Walk to the BACK-RIGHT corner.',
    'Walk to the BACK-LEFT corner.',
  ];

  @override
  void initState() {
    super.initState();
    _initCamera();
    _startSensors();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.8, end: 1.1).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  // ── Init ───────────────────────────────────────────────────────────────────

  Future<void> _initCamera() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        if (mounted) setState(() => _initError = 'No cameras found');
        return;
      }
      _camera = CameraController(cams[0], ResolutionPreset.medium, enableAudio: false);
      await _camera!.initialize();
      if (mounted) setState(() => _cameraInitialized = true);
    } catch (e) {
      if (mounted) setState(() => _initError = 'Camera init failed: $e');
    }
  }

  void _startSensors() {
    // GPS — highest accuracy, no distance filter (want every update)
    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      ),
    ).listen(
      (p) {
        if (mounted) setState(() => _pos = p);
      },
      onError: (e) {
        debugPrint('GPS stream error: $e');
      },
    );

    // Compass
    _compassSub = FlutterCompass.events?.listen((e) {
      if (mounted) setState(() => _heading = e.heading ?? _heading);
    });

    // Accelerometer (m/s²)
    _accelSub = accelerometerEventStream().listen((e) {
      if (mounted) setState(() { _accelX = e.x; _accelY = e.y; _accelZ = e.z; });
    });

    // Gyroscope (rad/s)
    _gyroSub = gyroscopeEventStream().listen((e) {
      if (mounted) setState(() { _gyroX = e.x; _gyroY = e.y; _gyroZ = e.z; });
    });

    // Magnetometer (µT)
    _magSub = magnetometerEventStream().listen((e) {
      if (mounted) setState(() { _magX = e.x; _magY = e.y; _magZ = e.z; });
    });

    // Barometer (hPa) — sensors_plus ≥ 3.x exposes barometerEventStream
    try {
      barometerEventStream().listen((e) {
        if (mounted) setState(() => _baroPressure = e.pressure);
      });
    } catch (_) {}
  }

  // ── Accuracy helpers ───────────────────────────────────────────────────────

  bool get _gpsReady => _pos != null && _pos!.accuracy <= 15;

  Color _accuracyColor(double acc) {
    if (acc <= 5)  return AppColors.success;
    if (acc <= 10) return Colors.lightGreen;
    if (acc <= 15) return Colors.orange;
    return AppColors.danger;
  }

  // ── Capture one corner ────────────────────────────────────────────────────

  Future<void> _captureCorner() async {
    if (_pos == null || _capturing) return;
    setState(() { _capturing = true; _captureErr = null; });

    // Compute device pitch from accelerometer (angle from horizontal)
    final pitch = math.atan2(-_accelX,
            math.sqrt(_accelY * _accelY + _accelZ * _accelZ)) *
        (180 / math.pi);
    final roll = math.atan2(_accelY, _accelZ) * (180 / math.pi);

    final corner = CornerData(
      lat:              _pos!.latitude,
      lng:              _pos!.longitude,
      alt:              _pos!.altitude,
      accuracy:         _pos!.accuracy,
      altitudeAccuracy: _pos!.altitudeAccuracy ?? 5.0,
      heading:          _heading,
      pitch:            pitch,
      roll:             roll,
      yaw:              _heading,        // yaw ≈ compass heading in NED frame
      accelerometer:    {'x': _accelX, 'y': _accelY, 'z': _accelZ},
      gyroscope:        {'x': _gyroX,  'y': _gyroY,  'z': _gyroZ},
      magneticField:    {'x': _magX,   'y': _magY,   'z': _magZ},
      barometricPressure: _baroPressure,
    );

    setState(() {
      _captured.add(corner);
      _capturing = false;
    });

    if (_captured.length == 4) {
      // All done — return to caller
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) {
        widget.onCaptureComplete(_captured);
        Navigator.pop(context);
      }
    } else {
      setState(() => _step = _captured.length);
    }
  }

  // ── Undo last corner ─────────────────────────────────────────────────────

  void _undoLastCorner() {
    if (_captured.isEmpty) return;
    setState(() {
      _captured.removeLast();
      _step = _captured.length;
    });
  }

  // ── Dispose ────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _camera?.dispose();
    _gpsSub?.cancel();
    _compassSub?.cancel();
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _magSub?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_initError != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.camera_alt_outlined, color: Colors.white54, size: 64),
                const SizedBox(height: 16),
                Text(_initError!, style: const TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_cameraInitialized || _camera == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Camera preview ───────────────────────────────────────
          CameraPreview(_camera!),

          // ── Dark scrim at top + bottom ───────────────────────────
          Column(
            children: [
              _buildTopHud(),
              const Spacer(),
              _buildBottomPanel(),
            ],
          ),

          // ── Corner reticle ───────────────────────────────────────
          Center(child: _buildReticle()),
        ],
      ),
    );
  }

  // ── Top HUD ────────────────────────────────────────────────────────────────

  Widget _buildTopHud() {
    final acc = _pos?.accuracy ?? 99;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            children: [
              // Progress bar
              Row(
                children: List.generate(4, (i) {
                  final done    = i < _captured.length;
                  final current = i == _step && _captured.length < 4;
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      height: 4,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: done
                            ? AppColors.success
                            : current
                                ? AppColors.primaryLight
                                : Colors.white24,
                      ),
                    ),
                  );
                }),
              ),

              const SizedBox(height: 14),

              // Sensor readouts
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _HudChip(
                        icon: Icons.gps_fixed,
                        label: 'GPS',
                        value: _pos == null
                            ? 'Searching…'
                            : '±${acc.toStringAsFixed(1)}m',
                        color: _pos == null ? Colors.orange : _accuracyColor(acc),
                      ),
                      const SizedBox(height: 6),
                      _HudChip(
                        icon: Icons.height,
                        label: 'Alt',
                        value: _pos == null
                            ? '---'
                            : '${_pos!.altitude.toStringAsFixed(1)}m',
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _HudChip(
                        icon: Icons.explore,
                        label: 'Heading',
                        value: '${_heading.toStringAsFixed(0)}°',
                      ),
                      const SizedBox(height: 6),
                      _HudChip(
                        icon: Icons.compress,
                        label: 'Baro',
                        value: _baroPressure == null
                            ? 'N/A'
                            : '${_baroPressure!.toStringAsFixed(1)} hPa',
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // GPS accuracy warning
              if (!_gpsReady)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Colors.orange, size: 14),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _pos == null
                              ? 'Acquiring GPS signal…'
                              : 'Move to open sky for better accuracy (${_pos!.accuracy.toStringAsFixed(1)}m)',
                          style: const TextStyle(
                              color: Colors.orange, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Reticle ────────────────────────────────────────────────────────────────

  Widget _buildReticle() {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) => Transform.scale(
        scale: _gpsReady ? _pulse.value : 1.0,
        child: Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: _gpsReady
                  ? AppColors.success.withOpacity(0.85)
                  : Colors.white38,
              width: 2,
            ),
          ),
          child: Center(
            child: Icon(
              Icons.add,
              color: _gpsReady ? AppColors.success : Colors.white38,
              size: 44,
            ),
          ),
        ),
      ),
    );
  }

  // ── Bottom panel ───────────────────────────────────────────────────────────

  Widget _buildBottomPanel() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black, Colors.black87, Colors.transparent],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Captured corners chips
              if (_captured.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  children: List.generate(_captured.length, (i) {
                    final c = _captured[i];
                    return _CornerChip(
                      label: _labels[i],
                      accuracy: c.accuracy,
                    );
                  }),
                ),
                const SizedBox(height: 16),
              ],

              // Step label
              if (_step < 4)
                Text(
                  'STEP ${_step + 1} / 4 — ${_labels[_step]}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              const SizedBox(height: 6),
              if (_step < 4)
                Text(
                  _hints[_step],
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),

              const SizedBox(height: 20),

              // Error
              if (_captureErr != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _captureErr!,
                    style: const TextStyle(color: AppColors.danger, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),

              // Action buttons
              Row(
                children: [
                  // Cancel button
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(color: Colors.grey.shade700),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  // Undo button (show if we have captured corners)
                  if (_captured.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 52,
                      height: 52,
                      child: IconButton(
                        onPressed: _undoLastCorner,
                        icon: const Icon(Icons.undo_rounded, color: Colors.orange),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.orange.withOpacity(0.1),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.orange.withOpacity(0.3)),
                          ),
                        ),
                      ),
                    ),
                  ],
                  // Capture button
                  if (_gpsReady && _step < 4) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _capturing ? null : _captureCorner,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryLight,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _capturing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : Text(
                                _step == 3 ? 'FINISH CAPTURE' : 'CAPTURE CORNER',
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────────

class _HudChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  const _HudChip({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color ?? Colors.white70, size: 14),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        Text(
          value,
          style: TextStyle(
            color: color ?? Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _CornerChip extends StatelessWidget {
  final String label;
  final double accuracy;

  const _CornerChip({required this.label, required this.accuracy});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.success.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_rounded,
              color: AppColors.success, size: 13),
          const SizedBox(width: 5),
          Text(
            '$label (±${accuracy.toStringAsFixed(1)}m)',
            style: const TextStyle(
                color: AppColors.success,
                fontSize: 11,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}