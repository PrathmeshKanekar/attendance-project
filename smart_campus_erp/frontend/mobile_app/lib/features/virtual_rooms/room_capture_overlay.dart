import 'dart:async';
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

class _RoomCaptureOverlayState extends State<RoomCaptureOverlay> {
  CameraController? _cameraController;
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<CompassEvent>? _compassStream;
  
  Position? _currentPosition;
  double _currentHeading = 0.0;
  List<CornerData> _capturedCorners = [];
  
  final List<String> _cornerLabels = ['Corner A', 'Corner B', 'Corner C', 'Corner D'];
  int _currentStep = 0;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _startLocationTracking();
    _startCompassTracking();
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    _cameraController = CameraController(
      cameras[0],
      ResolutionPreset.medium,
      enableAudio: false,
    );

    try {
      await _cameraController!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Camera initialization error: $e');
    }
  }

  void _startLocationTracking() {
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
      ),
    ).listen((Position position) {
      if (mounted) {
        setState(() {
          _currentPosition = position;
        });
      }
    });
  }

  void _startCompassTracking() {
    _compassStream = FlutterCompass.events?.listen((event) {
      if (mounted) {
        setState(() {
          _currentHeading = event.heading ?? 0.0;
        });
      }
    });
  }

  void _captureCorner() {
    if (_currentPosition == null) return;

    final corner = CornerData(
      lat: _currentPosition!.latitude,
      lng: _currentPosition!.longitude,
      alt: _currentPosition!.altitude,
      heading: _currentHeading,
      accuracy: _currentPosition!.accuracy,
    );

    setState(() {
      _capturedCorners.add(corner);
      if (_currentStep < 3) {
        _currentStep++;
      } else {
        widget.onCaptureComplete(_capturedCorners);
        Navigator.pop(context);
      }
    });
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _positionStream?.cancel();
    _compassStream?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera Preview
          Center(
            child: CameraPreview(_cameraController!),
          ),

          // Overlay HUD
          SafeArea(
            child: Column(
              children: [
                // Header Status
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.black54,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _StatusItem(
                            icon: Icons.gps_fixed,
                            label: 'GPS Acc:',
                            value: '${_currentPosition?.accuracy.toStringAsFixed(1) ?? "--"}m',
                            color: (_currentPosition?.accuracy ?? 100) < 10 ? AppColors.success : Colors.orange,
                          ),
                          _StatusItem(
                            icon: Icons.height,
                            label: 'Alt:',
                            value: '${_currentPosition?.altitude.toStringAsFixed(1) ?? "--"}m',
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _StatusItem(
                            icon: Icons.explore,
                            label: 'Heading:',
                            value: '${_currentHeading.toStringAsFixed(0)}°',
                          ),
                          _StatusItem(
                            icon: Icons.layers,
                            label: 'Captured:',
                            value: '${_capturedCorners.length}/4',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Guidance and Controls
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: const BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'STEP ${_currentStep + 1}: Stand at ${_cornerLabels[_currentStep]}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Ensure you are physically at the classroom corner for maximum accuracy.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 24),
                      
                      // Progress Indicators
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(4, (index) {
                          bool isDone = index < _capturedCorners.length;
                          bool isCurrent = index == _currentStep;
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: 40,
                            height: 6,
                            decoration: BoxDecoration(
                              color: isDone 
                                ? AppColors.success 
                                : (isCurrent ? AppColors.primaryLight : Colors.white24),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          );
                        }),
                      ),
                      
                      const SizedBox(height: 32),

                      // Action Buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white24),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton.icon(
                              onPressed: _currentPosition == null ? null : _captureCorner,
                              icon: const Icon(Icons.camera_alt),
                              label: Text('Capture ${_cornerLabels[_currentStep]}'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryLight,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Target Reticle
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white54, width: 2),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(Icons.add, color: Colors.white54, size: 40),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  const _StatusItem({
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
        Icon(icon, color: color ?? Colors.white70, size: 16),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(width: 4),
        Text(
          value, 
          style: TextStyle(
            color: color ?? Colors.white, 
            fontSize: 12, 
            fontWeight: FontWeight.bold
          )
        ),
      ],
    );
  }
}
