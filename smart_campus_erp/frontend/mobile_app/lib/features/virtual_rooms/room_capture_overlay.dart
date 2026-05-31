import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'services/sensor_fusion_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODEL
// ─────────────────────────────────────────────────────────────────────────────
class RoomCornerReading {
  final double latitude;
  final double longitude;
  final double altitude;
  final double heading;
  final double accuracy;
  
  // High precision telemetry logs
  final double gyroX;
  final double gyroY;
  final double gyroZ;
  final double accelX;
  final double accelY;
  final double accelZ;
  final String directionLabel;

  const RoomCornerReading({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.heading,
    required this.accuracy,
    this.gyroX = 0.0,
    this.gyroY = 0.0,
    this.gyroZ = 0.0,
    this.accelX = 0.0,
    this.accelY = 0.0,
    this.accelZ = 0.0,
    this.directionLabel = 'N',
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGET
// ─────────────────────────────────────────────────────────────────────────────
class RoomCaptureOverlay extends StatefulWidget {
  final int cornerIndex;
  final Function(RoomCornerReading) onCaptured;
  final VoidCallback onCancel;

  /// All previously captured corners — used for relative guidance warnings, NEVER rejections
  final List<RoomCornerReading> allCapturedCorners;

  const RoomCaptureOverlay({
    Key? key,
    required this.cornerIndex,
    required this.onCaptured,
    required this.onCancel,
    this.allCapturedCorners = const [],
  }) : super(key: key);

  @override
  State<RoomCaptureOverlay> createState() => _RoomCaptureOverlayState();
}

class _RoomCaptureOverlayState extends State<RoomCaptureOverlay> {
  final SensorFusionService _sensorFusionService = SensorFusionService();
  StreamSubscription<FusedSensorReading>? _fusionSub;
  Timer? _ticker;

  // Live state
  FusedSensorReading? _currentFusedReading;
  int _elapsedSeconds = 0;
  bool _isListening = false;

  // UI state
  String _statusText = 'Tap "Start High-Precision Calibration" to start';
  String _warningText = '';
  bool _hasWarning = false;
  bool _isCompleted = false;

  @override
  void dispose() {
    _fusionSub?.cancel();
    _ticker?.cancel();
    _sensorFusionService.stopTracking();
    super.dispose();
  }

  // ── Start Sensor Fusion Tracking ──────────────────────────────────────────
  Future<void> _startCalibration() async {
    await _fusionSub?.cancel();
    _ticker?.cancel();

    setState(() {
      _isListening = true;
      _currentFusedReading = null;
      _elapsedSeconds = 0;
      _hasWarning = false;
      _warningText = '';
      _isCompleted = false;
      _statusText = 'Fusing sensors & calibrating...';
    });

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedSeconds++);
    });

    try {
      await _sensorFusionService.startTracking();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isListening = false;
          _hasWarning = true;
          _warningText = e.toString().replaceFirst('Exception: ', '');
          _statusText = 'Location Permission Required';
        });

        // If permanently denied, offer to open app settings
        if (e.toString().contains('permanently denied')) {
          Geolocator.openAppSettings();
        }
      }
      return;
    }

    _fusionSub = _sensorFusionService.fusedStream.listen(
      (FusedSensorReading reading) {
        if (!mounted || _isCompleted) return;

        setState(() {
          _currentFusedReading = reading;
          
          // Compute status message
          final acc = reading.gpsAccuracy;
          if (acc <= 3) {
            _statusText = '99.9% High Precision Calibrated';
          } else if (acc <= 10) {
            _statusText = 'Optimal Fusion Quality Achieved';
          } else {
            _statusText = 'Stabilizing (Accuracy ±${acc.toStringAsFixed(1)}m)';
          }

          // Warnings are strictly advisory, NEVER blocking
          if (!reading.isStationary) {
            _hasWarning = true;
            _warningText = '⚠️ Keep device steady! Motion jitter detected.';
          } else if (acc > 20.0) {
            _hasWarning = true;
            _warningText = '⚠️ Weak GPS signal detected. Move to clear window if possible.';
          } else {
            _hasWarning = false;
            _warningText = '';
          }
        });
      },
      onError: (err) {
        if (mounted) {
          setState(() {
            _isListening = false;
            _statusText = 'Fusion error: $err';
          });
        }
      },
    );
  }

  // ── User accepts current calibrated fix ───────────────────────────────────
  void _acceptCurrentFix() {
    final r = _currentFusedReading;
    if (r == null) return;

    // Check distance only to show soft guide warnings, NEVER to block creation!
    for (int i = 0; i < widget.allCapturedCorners.length; i++) {
      final prev = widget.allCapturedCorners[i];
      final dist = Geolocator.distanceBetween(
        prev.latitude, prev.longitude,
        r.latitude, r.longitude,
      );
      if (dist < 0.5) {
        debugPrint('Advisory: Corner is extremely close to Corner ${i + 1} ($dist m). Proceeding anyway.');
      }
    }

    _commit(r);
  }

  // ── Final Commit ──────────────────────────────────────────────────────────
  void _commit(FusedSensorReading reading) {
    _fusionSub?.cancel();
    _ticker?.cancel();
    _sensorFusionService.stopTracking();

    setState(() {
      _isCompleted = true;
      _isListening = false;
      _statusText = '✅ Corner ${widget.cornerIndex} Calibrated & Saved!';
      _hasWarning = false;
    });

    final corner = RoomCornerReading(
      latitude: reading.latitude,
      longitude: reading.longitude,
      altitude: reading.altitude,
      heading: reading.compassDegrees,
      accuracy: reading.gpsAccuracy,
      gyroX: reading.gyroscope.x,
      gyroY: reading.gyroscope.y,
      gyroZ: reading.gyroscope.z,
      accelX: reading.accelerometer.x,
      accelY: reading.accelerometer.y,
      accelZ: reading.accelerometer.z,
      directionLabel: reading.directionLabel,
    );

    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) widget.onCaptured(corner);
    });
  }

  Color _getAccuracyColor(double acc) {
    if (acc <= 5) return Colors.tealAccent.shade700;
    if (acc <= 15) return Colors.greenAccent.shade400;
    if (acc <= 30) return Colors.amberAccent.shade400;
    return Colors.redAccent;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reading = _currentFusedReading;
    final acc = reading?.gpsAccuracy ?? 99.9;

    return Container(
      color: Colors.black.withOpacity(0.75),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.94,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A), // Premium Dark Slate Background
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: theme.primaryColor.withOpacity(0.2), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.6),
                  blurRadius: 30,
                  offset: const Offset(0, 15),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Top Header Badge ────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: theme.primaryColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'CORNER ${widget.cornerIndex} / 4',
                        style: TextStyle(
                          color: theme.primaryColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      onPressed: widget.onCancel,
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // ── High Tech Compass & Stabilization Dial ─────────────────
                Container(
                  height: 140,
                  width: 140,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF1E293B),
                    border: Border.all(
                      color: reading != null
                          ? _getAccuracyColor(acc)
                          : theme.primaryColor.withOpacity(0.3),
                      width: 3,
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Grid background decoration inside dial
                      Opacity(
                        opacity: 0.15,
                        child: Icon(Icons.grid_3x3_rounded, size: 90, color: theme.primaryColor),
                      ),
                      // Rotating compass needle
                      Transform.rotate(
                        angle: -((reading?.compassDegrees ?? 0.0) * math.pi / 180.0),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              height: 110,
                              width: 110,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                              ),
                            ),
                            // North marker arrow
                            Positioned(
                              top: 2,
                              child: Column(
                                children: [
                                  const Icon(Icons.arrow_drop_up_rounded, size: 24, color: Colors.redAccent),
                                  Text(
                                    'N',
                                    style: TextStyle(
                                      color: Colors.redAccent.shade200,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Core telemetries overlay
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${(reading?.compassDegrees ?? 0.0).toStringAsFixed(0)}°',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                            ),
                          ),
                          Text(
                            reading?.directionLabel ?? 'CAL',
                            style: TextStyle(
                              color: theme.primaryColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Centered Title & Instructions ──────────────────────────
                Text(
                  _statusText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),

                // ── Motion Stabilization Telemetry HUD ──────────────────────
                if (reading != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: Column(
                      children: [
                        // GPS Coords
                        _buildHudRow('LATITUDE', reading.latitude.toStringAsFixed(8)),
                        _buildHudRow('LONGITUDE', reading.longitude.toStringAsFixed(8)),
                        _buildHudRow('ALTITUDE', '${reading.altitude.toStringAsFixed(1)} m'),
                        _buildHudRow('GPS PRECISION', '±${reading.gpsAccuracy.toStringAsFixed(2)} m'),
                        const Divider(color: Colors.white12, height: 16),
                        // Accelerometer & Gyro
                        _buildHudRow(
                          'GYROSCOPE JITTER', 
                          'X: ${reading.gyroscope.x.toStringAsFixed(2)} | Y: ${reading.gyroscope.y.toStringAsFixed(2)}',
                        ),
                        _buildHudRow(
                          'STABILIZATION SCORE', 
                          '${((1.0 - reading.motionVariance.clamp(0.0, 1.0)) * 100.0).toStringAsFixed(0)}%',
                        ),
                        const SizedBox(height: 8),
                        // Motion state bar
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: reading.motionVariance.clamp(0.0, 1.0),
                            backgroundColor: Colors.white12,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              reading.isStationary ? Colors.tealAccent.shade400 : Colors.orangeAccent,
                            ),
                            minHeight: 5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // ── Warning banner (if any) ─────────────────────────────────
                if (_hasWarning && _warningText.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orangeAccent.withOpacity(0.3)),
                    ),
                    child: Text(
                      _warningText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // ── Calibration & Capture Controls ─────────────────────────
                if (!_isListening && !_isCompleted) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _startCalibration,
                      icon: const Icon(Icons.spatial_audio_off_rounded),
                      label: const Text(
                        'Start High-Precision Calibration',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                ],

                if (_isListening && !_isCompleted) ...[
                  // ACCEPT button — always works, warnings are soft
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: reading != null ? _acceptCurrentFix : null,
                      icon: const Icon(Icons.check_circle_rounded),
                      label: Text(
                        reading != null 
                            ? 'Capture & Freeze Corner $acc m' 
                            : 'Fusing Telemetries...',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: reading != null 
                            ? _getAccuracyColor(acc) 
                            : Colors.grey.shade800,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // RESTART calibration
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _startCalibration,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Recalibrate Sensors'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white30),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHudRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.white54, fontWeight: FontWeight.bold)),
          Text(value, style: const TextStyle(fontSize: 11, color: Colors.white, fontFamily: 'monospace', fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}