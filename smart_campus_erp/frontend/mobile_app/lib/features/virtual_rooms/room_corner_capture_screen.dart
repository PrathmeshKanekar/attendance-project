import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import '../../core/constants/app_colors.dart';
import 'room_capture_provider.dart';
import 'room_preview_screen.dart';

class RoomCornerCaptureScreen extends ConsumerStatefulWidget {
  final String roomId;
  final String roomName;

  const RoomCornerCaptureScreen({
    super.key,
    required this.roomId,
    required this.roomName,
  });

  @override
  ConsumerState<RoomCornerCaptureScreen> createState() => _RoomCornerCaptureScreenState();
}

class _RoomCornerCaptureScreenState extends ConsumerState<RoomCornerCaptureScreen> {
  CameraController? _controller;
  bool _isCameraReady = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    _controller = CameraController(cameras[0], ResolutionPreset.high);
    await _controller!.initialize();
    if (mounted) {
      setState(() => _isCameraReady = true);
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
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => RoomPreviewScreen(roomId: widget.roomId),
          ),
        );
      }
    });

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Camera Background
          if (_isCameraReady)
            SizedBox.expand(
              child: CameraPreview(_controller!),
            )
          else
            const Center(child: CircularProgressIndicator()),

          // 2. HUD Overlay
          SafeArea(
            child: Column(
              children: [
                _buildHeader(state),
                const Spacer(),
                _buildSensorsHud(),
                _buildActionButtons(state),
              ],
            ),
          ),
          
          if (state.isCapturing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppColors.primary),
                    SizedBox(height: 16),
                    Text('Capturing Spatial Data...', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(RoomCaptureState state) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              Column(
                children: [
                  Text(
                    widget.roomName,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Step ${state.currentCorner} of 4',
                    style: TextStyle(color: AppColors.primary, fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(width: 48),
            ],
          ),
          const SizedBox(height: 20),
          _buildProgressIndicator(state.currentCorner),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator(int current) {
    return Row(
      children: List.generate(4, (index) {
        final isActive = index + 1 == current;
        final isDone = index + 1 < current;
        return Expanded(
          child: Container(
            height: 4,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: isDone ? AppColors.primary : (isActive ? Colors.white : Colors.white24),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildSensorsHud() {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _sensorItem(Icons.gps_fixed, 'GPS', '±2.4m'),
              _sensorItem(Icons.height, 'ALT', '24.5m'),
              _sensorItem(Icons.explore, 'HDG', '182°'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sensorItem(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, color: Colors.white54, size: 20),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildActionButtons(RoomCaptureState state) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
      child: Column(
        children: [
          Text(
            'Walk to Corner ${state.currentCorner} and hold device steady',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () => ref.read(roomCaptureProvider.notifier).captureCorner(widget.roomId),
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
              ),
              child: Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.location_on, color: Colors.white, size: 32),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
