import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'package:go_router/go_router.dart';
import 'dart:ui';
import 'room_capture_provider.dart';
import '../../core/constants/app_colors.dart';

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
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;
    _controller = CameraController(cameras.first, ResolutionPreset.high);
    await _controller!.initialize();
    if (mounted) setState(() => _isInit = true);
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

    if (!_isInit) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Camera Preview
          Positioned.fill(child: CameraPreview(_controller!)),

          // 2. Futuristic Overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary.withOpacity(0.3), width: 2),
              ),
              child: CustomPaint(painter: HUDPainter()),
            ),
          ),

          // 3. Sensor HUD (Glassmorphism)
          Positioned(
            top: 60,
            left: 20,
            right: 20,
            child: _buildSensorPanel(),
          ),

          // 4. Progress Indicator
          Positioned(
            bottom: 120,
            left: 0,
            right: 0,
            child: _buildProgressDots(state.currentCorner),
          ),

          // 5. Action Button
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: _buildCaptureButton(state.isCapturing, state.currentCorner),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSensorPanel() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.4),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _sensorItem(Icons.gps_fixed, 'GPS', 'Best'),
              _sensorItem(Icons.height, 'ALT', '124m'),
              _sensorItem(Icons.explore, 'DIR', 'NE 45°'),
              _sensorItem(Icons.sensors, 'ACC', '9.81'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sensorItem(IconData icon, String label, String val) {
    return Column(
      children: [
        Icon(icon, color: AppColors.primaryLight, size: 20),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
        Text(val, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
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
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDone ? Colors.green : (isActive ? AppColors.primary : Colors.white24),
            border: Border.all(color: Colors.white54),
          ),
        );
      }),
    );
  }

  Widget _buildCaptureButton(bool loading, int corner) {
    return GestureDetector(
      onTap: () => ref.read(roomCaptureProvider.notifier).captureCorner(widget.roomId),
      child: Container(
        width: 80,
        height: 80,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
        ),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: loading ? Colors.grey : AppColors.primary,
          ),
          child: Center(
            child: loading 
              ? const CircularProgressIndicator(color: Colors.white)
              : Text('C$corner', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 24)),
          ),
        ),
      ),
    );
  }
}

class HUDPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary.withOpacity(0.5)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Corner brackets
    const d = 40.0;
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

    // Crosshair
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(center, 5, paint);
    canvas.drawLine(center - const Offset(20, 0), center - const Offset(10, 0), paint);
    canvas.drawLine(center + const Offset(10, 0), center + const Offset(20, 0), paint);
    canvas.drawLine(center - const Offset(0, 20), center - const Offset(0, 10), paint);
    canvas.drawLine(center + const Offset(0, 10), center + const Offset(0, 20), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
