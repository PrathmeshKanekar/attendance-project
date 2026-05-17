// presentation/screens/room_capture_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Real-time camera HUD capture interface.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'package:go_router/go_router.dart';
import 'dart:ui';

import '../../../../core/constants/app_colors.dart';
import '../providers/room_capture_provider.dart';

class RoomCaptureScreen extends ConsumerStatefulWidget {
  final String roomId;
  const RoomCaptureScreen({super.key, required this.roomId});

  @override
  ConsumerState<RoomCaptureScreen> createState() => _RoomCaptureScreenState();
}

class _RoomCaptureScreenState extends ConsumerState<RoomCaptureScreen> {
  CameraController? _controller;
  bool _isInit = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      _controller = CameraController(cameras.first, ResolutionPreset.high, enableAudio: false);
      await _controller!.initialize();
      if (mounted) setState(() => _isInit = true);
    } catch (e) {
      print('Camera initialization error: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(roomCaptureProvider);
    
    ref.listen(roomCaptureProvider, (prev, next) {
      if (next.isComplete) {
        context.pushReplacement('/virtual-rooms/${widget.roomId}/preview');
      }
      if (next.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.error!), backgroundColor: AppColors.danger),
        );
      }
    });

    if (!_isInit) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppColors.primaryLight),
              SizedBox(height: 16),
              Text('CALIBRATING SENSOR INTERFACES...', style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 1.0)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Full screen camera view
          Positioned.fill(child: CameraPreview(_controller!)),

          // 2. Neon HUD overlays
          Positioned.fill(
            child: CustomPaint(painter: HUDPainter()),
          ),

          // 3. Header HUD display (Glassmorphism)
          Positioned(
            top: 50,
            left: 20,
            right: 20,
            child: _buildHeaderSensorPanel(state),
          ),

          // 4. Progress indicators
          Positioned(
            bottom: 140,
            left: 0,
            right: 0,
            child: _buildProgressDots(state.currentCorner),
          ),

          // 5. Bottom action triggers
          Positioned(
            bottom: 40,
            left: 24,
            right: 24,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildSecondaryButton(
                  icon: Icons.undo_rounded,
                  label: 'Undo',
                  onTap: () => ref.read(roomCaptureProvider.notifier).undoLastCorner(),
                ),
                _buildCaptureButton(state.isCapturing, state.currentCorner),
                _buildSecondaryButton(
                  icon: Icons.close_rounded,
                  label: 'Cancel',
                  onTap: () => context.pop(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderSensorPanel(RoomCaptureState state) {
    final pos = state.currentPosition;
    final latStr = pos != null ? pos.latitude.toStringAsFixed(6) : 'WAITING...';
    final lngStr = pos != null ? pos.longitude.toStringAsFixed(6) : 'WAITING...';
    final altStr = pos != null ? '${pos.altitude.toStringAsFixed(1)}m' : 'WAITING...';
    final accStr = pos != null ? '${pos.accuracy.toStringAsFixed(1)}m' : 'WAITING...';
    final headStr = pos != null ? '${pos.heading.toStringAsFixed(0)}°' : 'WAITING...';
    final distStr = state.distanceToLastCorner != null 
        ? '${state.distanceToLastCorner!.toStringAsFixed(1)}m' 
        : 'N/A';

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.4),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: pos != null ? Colors.greenAccent : Colors.redAccent,
                          boxShadow: [
                            if (pos != null)
                              BoxShadow(
                                color: Colors.greenAccent.withOpacity(0.5),
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text('SPATIAL CALIBRATION GATEWAY', style: TextStyle(color: AppColors.primaryLight, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                    ],
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: (pos != null && pos.accuracy <= 20.0) 
                          ? Colors.green.withOpacity(0.2) 
                          : Colors.red.withOpacity(0.2), 
                      borderRadius: BorderRadius.circular(4)
                    ),
                    child: Text(
                      pos != null ? 'GPS LOCK' : 'TELEMETRY SEARCH', 
                      style: TextStyle(
                        color: (pos != null && pos.accuracy <= 20.0) ? Colors.greenAccent : Colors.redAccent, 
                        fontSize: 8, 
                        fontWeight: FontWeight.bold
                      )
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _sensorItem(Icons.gps_fixed_rounded, 'LAT/LNG', '$latStr, $lngStr'),
                  _sensorItem(Icons.height_rounded, 'ALTITUDE', altStr),
                  _sensorItem(Icons.explore_rounded, 'HEADING', headStr),
                  _sensorItem(Icons.track_changes_rounded, 'ACCURACY', accStr),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Captured Corners: ${state.capturedCorners.length} / 4',
                    style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Dist from Prev: $distStr',
                    style: TextStyle(
                      color: (state.distanceToLastCorner != null && state.distanceToLastCorner! >= 2.0) 
                          ? Colors.greenAccent 
                          : Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sensorItem(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 16),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 8)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildProgressDots(int current) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (index) {
        final isActive = index + 1 == current;
        final isDone = index + 1 < current;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDone 
                ? const Color(0xFF10B981) 
                : (isActive ? AppColors.primaryLight : Colors.white10),
            border: Border.all(
              color: isActive ? Colors.white : Colors.white24,
              width: 1.5,
            ),
            boxShadow: [
              if (isActive)
                BoxShadow(color: AppColors.primaryLight.withOpacity(0.4), blurRadius: 8),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildCaptureButton(bool loading, int corner) {
    return GestureDetector(
      onTap: () => ref.read(roomCaptureProvider.notifier).captureCorner(widget.roomId),
      child: Container(
        width: 76,
        height: 76,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
        ),
        child: Container(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primaryLight,
          ),
          child: Center(
            child: loading 
              ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 3))
              : Text('C$corner', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 22)),
          ),
        ),
      ),
    );
  }

  Widget _buildSecondaryButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(icon, color: Colors.white70),
          onPressed: onTap,
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withOpacity(0.1),
            padding: const EdgeInsets.all(12),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9)),
      ],
    );
  }
}

class HUDPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primaryLight.withOpacity(0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Corner brackets
    const d = 36.0;
    // Top Left
    canvas.drawLine(Offset.zero, const Offset(d, 0), paint);
    canvas.drawLine(Offset.zero, const Offset(0, d), paint);
    // Top Right
    canvas.drawLine(Offset(size.width, 0), Offset(size.width - d, 0), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, d), paint);
    // Bottom Left
    canvas.drawLine(Offset(0, size.height), Offset(d, size.height), paint);
    canvas.drawLine(Offset(0, size.height), Offset(0, size.height - d), paint);
    // Bottom Right
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width - d, size.height), paint);
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width, size.height - d), paint);

    // Crosshair target
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(center, 4, paint);
    canvas.drawLine(center - const Offset(16, 0), center - const Offset(8, 0), paint);
    canvas.drawLine(center + const Offset(8, 0), center + const Offset(16, 0), paint);
    canvas.drawLine(center - const Offset(0, 16), center - const Offset(0, 8), paint);
    canvas.drawLine(center + const Offset(0, 8), center + const Offset(0, 16), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
