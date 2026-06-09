import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'services/sensor_fusion_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ROOM CAPTURE / CORNER READING DATA MODEL
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
  final Function(RoomCornerReading) onCaptured;
  final VoidCallback onCancel;

  const RoomCaptureOverlay({
    Key? key,
    required this.onCaptured,
    required this.onCancel,
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

  // Multi-sample averaging state
  bool _isCapturing = false;
  int _sampleCount = 0;
  static const int _requiredSamples = 10; // Optimal 10 samples
  
  // Captured samples lists for filtering and outlier detection
  final List<double> _capturedLats = [];
  final List<double> _capturedLngs = [];
  final List<double> _capturedAlts = [];
  final List<double> _capturedAccs = [];
  final List<double> _capturedHeadings = [];

  // GPS Strategy Threshold Constants
  static const double _warmupMaxAccuracy = 100.0; // Phase 1: <= 100m
  static const double _stabilizationMaxAccuracy = 50.0; // Phase 2: <= 50m
  static const double _optimalAccuracyThreshold = 35.0; // Phase 3 (Room Creation target): <= 35m
  static const int _warmupDurationSeconds = 4; // 4 seconds warmup
  static const int _minRequiredSamplesForBypass = 3; // Minimum samples required to allow manual bypass

  // UI status & state variables
  String _statusText = 'Tap "Calibrate & Stabilize Center" to begin';
  String _warningText = '';
  bool _hasWarning = false;
  bool _isCompleted = false;
  double _lastGpsAccuracy = 999.0;
  bool _isImproving = false;
  double _bestAccuracy = 999.0;

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
      _isCapturing = true; // Auto-start capture upon calibration launch
      _sampleCount = 0;
      _statusText = 'Warming up GPS receiver...';
      _lastGpsAccuracy = 999.0;
      _bestAccuracy = 999.0;
      _isImproving = false;
      
      _capturedLats.clear();
      _capturedLngs.clear();
      _capturedAlts.clear();
      _capturedAccs.clear();
      _capturedHeadings.clear();
    });

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsedSeconds++;
        
        // Auto-finalize on timeout (30s hard limit)
        if (_elapsedSeconds >= 30 && !_isCompleted) {
          _finalizeCapture();
        }
      });
    });

    try {
      await _sensorFusionService.startTracking();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isListening = false;
          _hasWarning = true;
          _warningText = e.toString().replaceFirst('Exception: ', '');
          _statusText = 'GPS Initialization Failed';
        });
      }
      return;
    }

    _fusionSub = _sensorFusionService.fusedStream.listen(
      (FusedSensorReading reading) {
        if (!mounted || _isCompleted) return;

        setState(() {
          _currentFusedReading = reading;
          
          final acc = reading.gpsAccuracy;
          if (acc < _bestAccuracy) {
            _bestAccuracy = acc;
          }
          _isImproving = acc < _lastGpsAccuracy;
          _lastGpsAccuracy = acc;

          // Define dynamic status description based on warmup vs stabilization phases
          if (_elapsedSeconds <= _warmupDurationSeconds) {
            _statusText = 'GPS Warmup: Satellite Acquisition...';
          } else if (_elapsedSeconds >= 12) {
            _statusText = 'Using Best Available Location';
          } else {
            _statusText = 'Improving GPS Signal... (${_sampleCount}/${_requiredSamples})';
          }

          // Anti-noise and quality warnings
          if (!reading.isStationary) {
            _hasWarning = true;
            _warningText = '⚠️ Keep device steady in the room center for optimal calibration.';
          } else if (acc > _stabilizationMaxAccuracy && _elapsedSeconds > _warmupDurationSeconds) {
            _hasWarning = true;
            _warningText = '⚠️ High signal noise. Hold device flat to acquire better satellite line-of-sight.';
          } else {
            _hasWarning = false;
            _warningText = '';
          }
        });

        // Collect sample on genuine GPS ticks
        if (_isCapturing && !_isCompleted && reading.isGpsUpdate) {
          _collectSample(reading);
        }
      },
      onError: (err) {
        if (mounted) {
          setState(() {
            _isListening = false;
            _statusText = 'GPS Stream Error: $err';
          });
        }
      },
    );
  }

  // ── Collect and Process GPS Sample ─────────────────────────────────────────
  void _collectSample(FusedSensorReading reading) {
    final acc = reading.gpsAccuracy;
    final isWarmup = _elapsedSeconds <= _warmupDurationSeconds;

    // Apply adaptive GPS threshold strategy:
    // - During Warmup: accept rough fixes up to 120m to handle indoor drops
    // - During Stabilization: accept fixes up to 60m
    final double maxAllowedAccuracy = isWarmup ? 120.0 : 60.0;

    if (acc > maxAllowedAccuracy) {
      debugPrint('Adaptive GPS Filter: Dropped sample with low precision (acc=${acc.toStringAsFixed(1)}m, limit=${maxAllowedAccuracy}m)');
      return;
    }

    setState(() {
      _capturedLats.add(reading.latitude);
      _capturedLngs.add(reading.longitude);
      _capturedAlts.add(reading.altitude);
      _capturedAccs.add(reading.gpsAccuracy);
      _capturedHeadings.add(reading.compassDegrees);
      
      _sampleCount = _capturedLats.length;

      // Check validation phase:
      // Auto-finalize if we hit required samples OR if we have at least 5 samples and accuracy is already excellent
      if (_sampleCount >= _requiredSamples || 
          (_sampleCount >= 5 && acc <= _optimalAccuracyThreshold)) {
        _isCompleted = true;
        _isCapturing = false;
        _finalizeCapture();
      }
    });
  }

  // ── Post-Processing & Smoothing of Captured Samples ────────────────────────
  void _finalizeCapture() async {
    _ticker?.cancel();
    _sensorFusionService.stopTracking();
    _fusionSub?.cancel();

    if (_capturedLats.isEmpty) {
      // ── TIMEOUT FALLBACK COGNIZANCE STRATEGY ──
      // Never trap the user! If no samples met the strict filtering limits but we received sensor fusion readings,
      // construct a corner result using the current best-effort reading.
      if (_currentFusedReading != null) {
        final result = RoomCornerReading(
          latitude: _currentFusedReading!.latitude,
          longitude: _currentFusedReading!.longitude,
          altitude: _currentFusedReading!.altitude,
          heading: _currentFusedReading!.compassDegrees,
          accuracy: _currentFusedReading!.gpsAccuracy,
          gyroX: _currentFusedReading!.gyroscope.x,
          gyroY: _currentFusedReading!.gyroscope.y,
          gyroZ: _currentFusedReading!.gyroscope.z,
          accelX: _currentFusedReading!.accelerometer.x,
          accelY: _currentFusedReading!.accelerometer.y,
          accelZ: _currentFusedReading!.accelerometer.z,
          directionLabel: _currentFusedReading!.directionLabel,
        );
        
        setState(() {
          _isCompleted = true;
          _isCapturing = false;
          _statusText = 'Using Best Available Location';
        });
        
        widget.onCaptured(result);
        return;
      }
      
      // Fallback: If even the live fused reading is null, retrieve best-effort native position immediately
      try {
        final lastKnown = await Geolocator.getLastKnownPosition() ??
                          await Geolocator.getCurrentPosition(
                              locationSettings: AndroidSettings(
                                accuracy: LocationAccuracy.low,
                                timeLimit: Duration(seconds: 3),
                              ));
                              
        final result = RoomCornerReading(
          latitude: lastKnown.latitude,
          longitude: lastKnown.longitude,
          altitude: lastKnown.altitude,
          heading: lastKnown.heading,
          accuracy: lastKnown.accuracy,
        );
        
        setState(() {
          _isCompleted = true;
          _isCapturing = false;
          _statusText = 'Using Best Available Location';
        });
        
        widget.onCaptured(result);
        return;
      } catch (e) {
        debugPrint('Fallback native geolocation retrieval failed: $e');
      }

      setState(() {
        _isListening = false;
        _statusText = 'Calibration failed: No GPS coordinate locks recorded.';
      });
      return;
    }

    setState(() {
      _isCompleted = true;
      _isCapturing = false;
    });

    // 1. Outlier filtering using Median Absolute Deviation (MAD)
    final medianLat = _calculateMedian(_capturedLats);
    final medianLng = _calculateMedian(_capturedLngs);

    final validLats = <double>[];
    final validLngs = <double>[];
    final validAlts = <double>[];
    final validAccs = <double>[];
    final validHeadings = <double>[];

    for (int i = 0; i < _capturedLats.length; i++) {
      // Calculate distance from median in meters (approximate geodetic distance)
      final dist = Geolocator.distanceBetween(
        medianLat,
        medianLng,
        _capturedLats[i],
        _capturedLngs[i],
      );

      // Rejection threshold: drop coordinate outliers that deviate by more than 20m from the median cluster
      if (dist < 20.0) {
        validLats.add(_capturedLats[i]);
        validLngs.add(_capturedLngs[i]);
        validAlts.add(_capturedAlts[i]);
        validAccs.add(_capturedAccs[i]);
        validHeadings.add(_capturedHeadings[i]);
      }
    }

    final finalLats = validLats.isNotEmpty ? validLats : _capturedLats;
    final finalLngs = validLngs.isNotEmpty ? validLngs : _capturedLngs;
    final finalAlts = validAlts.isNotEmpty ? validAlts : _capturedAlts;
    final finalAccs = validAccs.isNotEmpty ? validAccs : _capturedAccs;
    final finalHeadings = validHeadings.isNotEmpty ? validHeadings : _capturedHeadings;

    // 2. Compute circular and high-precision averages
    final avgLat = finalLats.reduce((a, b) => a + b) / finalLats.length;
    final avgLng = finalLngs.reduce((a, b) => a + b) / finalLngs.length;
    final avgAlt = finalAlts.reduce((a, b) => a + b) / finalAlts.length;
    final avgAcc = finalAccs.reduce((a, b) => a + b) / finalAccs.length;

    // Circular average to prevent compass boundary wrap-around bug (e.g. 359° and 1° correctly averages to 0°)
    final avgHeading = _calculateCircularAverage(finalHeadings);

    final result = RoomCornerReading(
      latitude: avgLat,
      longitude: avgLng,
      altitude: avgAlt,
      heading: avgHeading,
      accuracy: avgAcc,
      gyroX: _currentFusedReading?.gyroscope.x ?? 0.0,
      gyroY: _currentFusedReading?.gyroscope.y ?? 0.0,
      gyroZ: _currentFusedReading?.gyroscope.z ?? 0.0,
      accelX: _currentFusedReading?.accelerometer.x ?? 0.0,
      accelY: _currentFusedReading?.accelerometer.y ?? 0.0,
      accelZ: _currentFusedReading?.accelerometer.z ?? 0.0,
      directionLabel: _currentFusedReading?.directionLabel ?? 'N',
    );

    widget.onCaptured(result);
  }

  double _calculateMedian(List<double> values) {
    final sorted = List<double>.from(values)..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length % 2 == 1) {
      return sorted[middle];
    } else {
      return (sorted[middle - 1] + sorted[middle]) / 2.0;
    }
  }

  double _calculateCircularAverage(List<double> anglesDegrees) {
    double sinSum = 0.0;
    double cosSum = 0.0;

    for (final angle in anglesDegrees) {
      final rad = angle * math.pi / 180.0;
      sinSum += math.sin(rad);
      cosSum += math.cos(rad);
    }

    final avgRad = math.atan2(sinSum, cosSum);
    return (avgRad * 180.0 / math.pi + 360.0) % 360.0;
  }

  double _calculateConfidenceScore() {
    if (_capturedAccs.isEmpty) return 0.0;
    
    // Average accuracy
    final avgAcc = _capturedAccs.reduce((a, b) => a + b) / _capturedAccs.length;
    
    // Target room creation accuracy is <= 35m.
    // Confidence is 100% at 3m accuracy or below, falling to 10% at 50m accuracy.
    double score = 100.0 - (avgAcc - 3.0) * 1.91;
    
    // Variance penalty: if GPS is fluttering widely, apply minor penalty
    if (_capturedLats.length > 2) {
      double latSum = 0;
      for (var l in _capturedLats) {
        latSum += l;
      }
      double latAvg = latSum / _capturedLats.length;
      double varianceSum = 0;
      for (var l in _capturedLats) {
        varianceSum += (l - latAvg) * (l - latAvg);
      }
      double stdDev = math.sqrt(varianceSum / (_capturedLats.length - 1)) * 111000.0; // In meters
      score -= (stdDev * 3.0); // 3% penalty per meter of standard deviation
    }

    return score.clamp(10.0, 100.0);
  }

  Color _getAccuracyColor(double acc) {
    if (acc <= 15) return Colors.tealAccent.shade700;
    if (acc <= 35) return Colors.greenAccent.shade400;
    if (acc <= 50) return Colors.amberAccent.shade400;
    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reading = _currentFusedReading;
    final acc = reading?.gpsAccuracy ?? 99.9;
    final progress = _sampleCount / _requiredSamples;
    final confidence = _calculateConfidenceScore();
    
    // Enable override bypass button after 10 seconds of calibration
    final showBypassButton = _isListening && _elapsedSeconds >= 10;

    return Container(
      color: Colors.black.withOpacity(0.85),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.94,
            padding: const EdgeInsets.all(24),
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
                // ── Top Header ─────────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: theme.primaryColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.wifi_tethering_rounded, color: Colors.tealAccent, size: 14),
                          SizedBox(width: 6),
                          Text(
                            'GPS STABILIZATION ENGINE',
                            style: TextStyle(
                              color: Colors.tealAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      onPressed: widget.onCancel,
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // ── Compass Dial ───────────────────────────────────────────
                Container(
                  height: 150,
                  width: 150,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF1E293B),
                    border: Border.all(
                      color: reading != null
                          ? _getAccuracyColor(acc)
                          : theme.primaryColor.withOpacity(0.3),
                      width: 3.5,
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Opacity(
                        opacity: 0.15,
                        child: Icon(Icons.grid_3x3_rounded, size: 90, color: theme.primaryColor),
                      ),
                      Transform.rotate(
                        angle: -((reading?.compassDegrees ?? 0.0) * math.pi / 180.0),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              height: 120,
                              width: 120,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                              ),
                            ),
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
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${(reading?.compassDegrees ?? 0.0).toStringAsFixed(0)}°',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
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
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ── Dynamic Improving Status HUD Message ───────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _statusText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_isListening && _isImproving) ...[
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.tealAccent),
                      ),
                    ]
                  ],
                ),
                const SizedBox(height: 8),

                // Signal indicator dynamic trending bar
                if (_isListening)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: (_isImproving ? Colors.teal : Colors.blueGrey).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: (_isImproving ? Colors.tealAccent : Colors.white24).withOpacity(0.2)),
                    ),
                    child: Text(
                      _isImproving ? '📈 Improving GPS signal...' : '⏳ Stabilizing signal lock...',
                      style: TextStyle(
                        color: _isImproving ? Colors.tealAccent : Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                if (_hasWarning)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.withOpacity(0.3)),
                    ),
                    child: Text(
                      _warningText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.amberAccent, fontSize: 11),
                    ),
                  ),

                // ── Calibration Progress bar ────────────────────────────────
                if (_isListening) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: const Color(0xFF334155),
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.tealAccent),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Live telemetries HUD
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _TelemetryCard(
                        title: 'ACCURACY',
                        value: reading != null ? '±${acc.toStringAsFixed(1)}m' : 'Calibrating',
                        color: _getAccuracyColor(acc),
                      ),
                      _TelemetryCard(
                        title: 'CONFIDENCE',
                        value: '${confidence.toStringAsFixed(0)}%',
                        color: confidence >= 70 ? Colors.tealAccent : Colors.orangeAccent,
                      ),
                      _TelemetryCard(
                        title: 'ELAPSED',
                        value: '${_elapsedSeconds}s',
                        color: Colors.white,
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 24),

                // ── GPS DEBUG PANEL ──────────────────────────────────────────
                if (_isListening) ...[
                  _buildDebugPanel(theme, acc, confidence),
                  const SizedBox(height: 20),
                ],

                // ── Action Buttons & Override Fallbacks ─────────────────────
                if (!_isListening)
                  ElevatedButton.icon(
                    onPressed: _startCalibration,
                    icon: const Icon(Icons.gps_fixed_rounded),
                    label: const Text('CALIBRATE & STABILIZE CENTER'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      minimumSize: const Size(double.infinity, 50),
                    ),
                  )
                else ...[
                  // Dynamic Override Bypass Trigger to prevent deadlocks
                  if (showBypassButton) ...[
                    ElevatedButton.icon(
                      onPressed: _finalizeCapture,
                      icon: const Icon(Icons.offline_pin_rounded, color: Colors.white),
                      label: const Text('USE BEST AVAILABLE LOCATION'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        minimumSize: const Size(double.infinity, 50),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  
                  OutlinedButton(
                    onPressed: () {
                      _ticker?.cancel();
                      _sensorFusionService.stopTracking();
                      _fusionSub?.cancel();
                      widget.onCancel();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white60,
                      side: const BorderSide(color: Color(0xFF334155)),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    child: const Text('ABORT CALIBRATION'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDebugPanel(ThemeData theme, double acc, double confidence) {
    final isWarmup = _elapsedSeconds <= _warmupDurationSeconds;
    final dynamicLimit = isWarmup ? 120.0 : 60.0;
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bug_report_rounded, color: Colors.tealAccent, size: 16),
              const SizedBox(width: 8),
              Text(
                'GPS CALIBRATION DEBUG PANEL',
                style: TextStyle(
                  color: Colors.tealAccent.shade200,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildDebugRow('Raw Accuracy', '±${acc.toStringAsFixed(1)}m', Colors.white70),
          _buildDebugRow('Best Accuracy', '±${_bestAccuracy == 999.0 ? "N/A" : _bestAccuracy.toStringAsFixed(1)}m', Colors.tealAccent),
          _buildDebugRow('Confidence', '${confidence.toStringAsFixed(0)}%', confidence >= 70 ? Colors.tealAccent : Colors.orangeAccent),
          _buildDebugRow('Samples Collected', '${_sampleCount} / ${_requiredSamples}', Colors.white70),
          _buildDebugRow('GPS Source', 'Fused Location Service', Colors.white70),
          _buildDebugRow('Warmup Status', isWarmup ? 'Active (First 4s coarse)' : 'Completed', isWarmup ? Colors.orangeAccent : Colors.tealAccent),
          _buildDebugRow('Stabilization Status', _sampleCount >= _requiredSamples ? 'Locked & Calibrated' : 'Smoothing & Outlier Rejection', Colors.white70),
          _buildDebugRow('Fallback Status', _elapsedSeconds >= 10 ? 'Available (10s elapsed)' : 'Acquiring (Pending)', _elapsedSeconds >= 10 ? Colors.tealAccent : Colors.white38),
          _buildDebugRow('Current Threshold', '≤ ${dynamicLimit.toStringAsFixed(0)}m (${isWarmup ? "Warmup" : "Stabilization"})', Colors.amberAccent),
        ],
      ),
    );
  }

  Widget _buildDebugRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w500)),
          Text(value, style: TextStyle(color: valueColor, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
        ],
      ),
    );
  }
}

class _TelemetryCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;

  const _TelemetryCard({
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.white54, fontSize: 8, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}