import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODEL
// ─────────────────────────────────────────────────────────────────────────────
class RoomCornerReading {
  final double latitude;
  final double longitude;
  final double altitude;
  final double heading;
  final double accuracy;

  const RoomCornerReading({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.heading,
    required this.accuracy,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGET
// ─────────────────────────────────────────────────────────────────────────────
class RoomCaptureOverlay extends StatefulWidget {
  final int cornerIndex;
  final Function(RoomCornerReading) onCaptured;
  final VoidCallback onCancel;

  /// All previously captured corners — used to enforce minimum distance check
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

// ─────────────────────────────────────────────────────────────────────────────
// STATE  — pure geolocator stream, NO location package, NO auto-accept
// ─────────────────────────────────────────────────────────────────────────────
class _RoomCaptureOverlayState extends State<RoomCaptureOverlay> {
  StreamSubscription<Position>? _positionSub;
  Timer? _ticker;

  // Live GPS state
  Position? _currentPosition;
  List<double> _accuracyHistory = [];
  int _elapsedSeconds = 0;
  bool _isListening = false;

  // UI state
  String _statusText = 'Tap "Capture GPS" to start';
  String _warningText = '';
  bool _hasWarning = false;
  bool _isCompleted = false;

  @override
  void dispose() {
    _positionSub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  // ── Start fresh GPS stream ──────────────────────────────────────────────
  Future<void> _startListening() async {
    // Cancel any previous stream cleanly
    await _positionSub?.cancel();
    _positionSub = null;
    _ticker?.cancel();

    setState(() {
      _isListening = true;
      _currentPosition = null;
      _accuracyHistory = [];
      _elapsedSeconds = 0;
      _hasWarning = false;
      _warningText = '';
      _isCompleted = false;
      _statusText = 'Acquiring GPS signal...';
    });

    // ── Permission check ────────────────────────────────────────────────
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        setState(() {
          _isListening = false;
          _statusText = 'GPS disabled. Enable location services.';
        });
      }
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() {
          _isListening = false;
          _statusText = 'Location permission denied.';
        });
      }
      return;
    }

    // ── Elapsed seconds ticker ──────────────────────────────────────────
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedSeconds++);
    });

    // ── KEY FIX: Use LocationSettings with best accuracy ──────────────
    // distanceFilter: 0  →  receive EVERY update, even if phone is still
    // accuracy: best     →  forces GPS chip, not WiFi/cell tower
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    );

    _positionSub = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (Position pos) {
        if (!mounted || _isCompleted) return;

        final acc = pos.accuracy;

        // Build accuracy history (only add if changed)
        if (_accuracyHistory.isEmpty ||
            (_accuracyHistory.last - acc).abs() > 0.5) {
          _accuracyHistory.add(acc);
        }

        setState(() {
          _currentPosition = pos;
          _statusText = _accuracyLabel(acc);
          _hasWarning = acc > 30.0;
          _warningText = acc > 30.0
              ? 'Weak signal (±${acc.toStringAsFixed(0)}m). '
                'Move near a window. Keep waiting or tap Accept.'
              : '';
        });

        debugPrint(
          '📍 GPS update  corner=${widget.cornerIndex}  '
          'lat=${pos.latitude.toStringAsFixed(7)}  '
          'lng=${pos.longitude.toStringAsFixed(7)}  '
          'acc=${acc.toStringAsFixed(1)}m  '
          't=${_elapsedSeconds}s',
        );
      },
      onError: (err) {
        debugPrint('GPS stream error: $err');
        if (mounted) {
          setState(() {
            _isListening = false;
            _statusText = 'GPS error: $err';
          });
        }
      },
    );
  }

  // ── User manually taps "Accept" ────────────────────────────────────────
  void _acceptCurrentFix() {
    final pos = _currentPosition;
    if (pos == null) return;

    // Distance check vs ALL previously captured corners
    for (int i = 0; i < widget.allCapturedCorners.length; i++) {
      final prev = widget.allCapturedCorners[i];
      final dist = Geolocator.distanceBetween(
        prev.latitude, prev.longitude,
        pos.latitude, pos.longitude,
      );
      if (dist < 1.0) {
        // Less than 1 metre away from a previous corner — refuse silently
        setState(() {
          _hasWarning = true;
          _warningText =
              '⚠️ Too close to Corner ${i + 1} (${dist.toStringAsFixed(1)}m). '
              'Walk further away and wait for GPS to update, then tap Accept again.';
        });
        debugPrint(
          '❌ Rejected: Corner ${widget.cornerIndex} is ${dist.toStringAsFixed(2)}m '
          'from Corner ${i + 1} — too close.',
        );
        return;
      }
    }

    _commit(pos);
  }

  // ── Final commit ───────────────────────────────────────────────────────
  void _commit(Position pos) {
    _positionSub?.cancel();
    _ticker?.cancel();

    debugPrint('═══════════════════════════════════════════════');
    debugPrint('✅ CORNER ${widget.cornerIndex} COMMITTED');
    debugPrint('   lat  = ${pos.latitude}');
    debugPrint('   lng  = ${pos.longitude}');
    debugPrint('   acc  = ${pos.accuracy.toStringAsFixed(1)}m');
    debugPrint('   time = ${_elapsedSeconds}s');
    debugPrint('═══════════════════════════════════════════════');

    setState(() {
      _isCompleted = true;
      _isListening = false;
      _statusText = '✅ Corner ${widget.cornerIndex} saved!';
      _hasWarning = false;
    });

    final reading = RoomCornerReading(
      latitude: pos.latitude,
      longitude: pos.longitude,
      altitude: pos.altitude,
      heading: pos.heading,
      accuracy: pos.accuracy,
    );

    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) widget.onCaptured(reading);
    });
  }

  // ── Helpers ────────────────────────────────────────────────────────────
  String _accuracyLabel(double acc) {
    if (acc <= 5) return 'Excellent — tap Accept';
    if (acc <= 15) return 'Good — tap Accept';
    if (acc <= 30) return 'Fair — you can Accept';
    if (acc <= 100) return 'Poor — wait or Accept anyway';
    return 'Very weak — move near window';
  }

  Color _accuracyColor(double acc) {
    if (acc <= 15) return Colors.green.shade600;
    if (acc <= 30) return Colors.amber.shade700;
    if (acc <= 100) return Colors.orange.shade600;
    return Colors.red.shade600;
  }

  // ─────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pos = _currentPosition;
    final acc = pos?.accuracy;

    return Container(
      color: Colors.black.withOpacity(0.65),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.92,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark
                  ? const Color(0xFF1E293B)
                  : Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Accuracy ring icon ──────────────────────────────
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: acc != null
                          ? _accuracyColor(acc)
                          : theme.primaryColor.withOpacity(0.3),
                      width: 5,
                    ),
                    color: (acc != null
                            ? _accuracyColor(acc)
                            : theme.primaryColor)
                        .withOpacity(0.08),
                  ),
                  child: Icon(
                    _isCompleted
                        ? Icons.check_circle_rounded
                        : (acc != null && acc <= 30
                            ? Icons.gps_fixed_rounded
                            : Icons.gps_not_fixed_rounded),
                    color: acc != null
                        ? _accuracyColor(acc)
                        : theme.primaryColor,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 14),

                // ── Corner title ────────────────────────────────────
                Text(
                  'Corner ${widget.cornerIndex}',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Walk to the corner, wait for GPS to update, then tap Accept.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.disabledColor,
                  ),
                ),
                const SizedBox(height: 20),

                // ── Elapsed time + spinner ──────────────────────────
                if (_isListening && !_isCompleted) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.primaryColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'GPS active — ${_elapsedSeconds}s',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.primaryColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Live coordinate ─────────────────────────────────
                if (pos != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _accuracyColor(pos.accuracy).withOpacity(0.07),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _accuracyColor(pos.accuracy).withOpacity(0.25),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Lat: ${pos.latitude.toStringAsFixed(7)}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Lng: ${pos.longitude.toStringAsFixed(7)}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '±${pos.accuracy.toStringAsFixed(1)} m accuracy',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: _accuracyColor(pos.accuracy),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // ── Accuracy history ────────────────────────────────
                if (_accuracyHistory.length > 1) ...[
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text(
                      _accuracyHistory
                          .map((e) => '±${e.toStringAsFixed(0)}m')
                          .join(' → '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: theme.disabledColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // ── Status text ─────────────────────────────────────
                Text(
                  _statusText,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: acc != null
                        ? _accuracyColor(acc)
                        : theme.primaryColor,
                  ),
                ),
                const SizedBox(height: 8),

                // ── Warning banner ──────────────────────────────────
                if (_hasWarning && _warningText.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.withOpacity(0.2)),
                    ),
                    child: Text(
                      _warningText,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.red.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),

                // ── Buttons ─────────────────────────────────────────
                if (!_isListening && !_isCompleted) ...[
                  // START button (shown before stream starts)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _startListening,
                      icon: const Icon(Icons.gps_fixed_rounded),
                      label: const Text(
                        'Start GPS',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                if (_isListening && !_isCompleted) ...[
                  // ACCEPT button — only active when we have a position
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: pos != null ? _acceptCurrentFix : null,
                      icon: const Icon(Icons.check_circle_rounded),
                      label: Text(
                        pos != null
                            ? 'Accept  (±${pos.accuracy.toStringAsFixed(0)}m)'
                            : 'Waiting for GPS...',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: pos != null
                            ? _accuracyColor(pos.accuracy)
                            : Colors.grey,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // RESTART button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _startListening,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Restart GPS'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // CANCEL always visible
                if (!_isCompleted)
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: widget.onCancel,
                      child: const Text('Cancel'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}