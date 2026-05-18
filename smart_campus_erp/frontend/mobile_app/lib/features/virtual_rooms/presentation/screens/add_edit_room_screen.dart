import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/layout/app_layout.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/loading_widget.dart';
import '../../models/virtual_room_model.dart';
import '../../providers/virtual_room_providers.dart';

class AddEditRoomScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? existingRoom;

  const AddEditRoomScreen({
    super.key,
    this.existingRoom,
  });

  @override
  ConsumerState<AddEditRoomScreen> createState() => _AddEditRoomScreenState();
}

class _AddEditRoomScreenState extends ConsumerState<AddEditRoomScreen> {
  final _formKey = GlobalKey<FormState>();
  
  late final TextEditingController _nameController;
  late final TextEditingController _buildingController;
  late final TextEditingController _deptController;
  late final TextEditingController _floorController;
  late final TextEditingController _capacityController;

  bool _isSaving = false;
  VirtualRoomModel? _room;

  @override
  void initState() {
    super.initState();
    
    // Map existing room map into a model if editing
    if (widget.existingRoom != null) {
      _room = VirtualRoomModel.fromJson(widget.existingRoom!);
    }

    _nameController = TextEditingController(text: _room?.name ?? '');
    _buildingController = TextEditingController(text: _room?.building ?? '');
    _deptController = TextEditingController(text: _room?.department ?? '');
    _floorController = TextEditingController(text: (_room?.floorNumber ?? 0).toString());
    _capacityController = TextEditingController(text: (_room?.capacity ?? 60).toString());

    // Initialize corner state if editing
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(roomCaptureProvider.notifier).reset();
      if (_room != null && _room!.corners.isNotEmpty) {
        ref.read(roomCaptureProvider.notifier).setExistingCorners(_room!.corners);
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _buildingController.dispose();
    _deptController.dispose();
    _floorController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  Future<void> _saveRoom() async {
    if (!_formKey.currentState!.validate()) return;

    final captureState = ref.read(roomCaptureProvider);
    final capturedCorners = captureState.corners.where((c) => c != null).toList();

    if (capturedCorners.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Exactly 4 corners must be captured. Currently captured: ${capturedCorners.length}/4',
          ),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    // Build corners request payload
    final cornerPayload = captureState.corners.map((c) {
      return {
        'corner_index': c!.cornerIndex,
        'latitude': c.latitude,
        'longitude': c.longitude,
        'altitude': c.altitude,
        'heading': c.heading,
        'accuracy': c.accuracy,
      };
    }).toList();

    // Auto-calculate center
    double avgLat = captureState.corners.map((c) => c!.latitude).reduce((a, b) => a + b) / 4.0;
    double avgLng = captureState.corners.map((c) => c!.longitude).reduce((a, b) => a + b) / 4.0;

    final Map<String, dynamic> body = {
      'name': _nameController.text.trim(),
      'building': _buildingController.text.trim(),
      'department': _deptController.text.trim(),
      'floor_number': int.tryParse(_floorController.text.trim()) ?? 0,
      'capacity': int.tryParse(_capacityController.text.trim()) ?? 60,
      'center_lat': avgLat,
      'center_lng': avgLng,
      'corner_coordinates': cornerPayload,
    };

    try {
      if (_room != null) {
        await ref.read(virtualRoomsListProvider.notifier).editRoom(_room!.id, body);
      } else {
        await ref.read(virtualRoomsListProvider.notifier).addRoom(body);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_room != null ? 'Virtual Room updated successfully!' : 'Virtual Room created successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save room: ${e.toString()}'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _triggerCapture(int cornerIndex) async {
    try {
      await ref.read(roomCaptureProvider.notifier).captureCorner(cornerIndex);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Corner $cornerIndex captured successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final captureState = ref.watch(roomCaptureProvider);
    final isEdit = _room != null;

    // Check if all 4 corners are captured
    final allCornersCaptured = captureState.corners.every((c) => c != null);

    return AppLayout(
      title: isEdit ? 'Edit Virtual Room' : 'Create Virtual Room',
      child: _isSaving
          ? const LoadingWidget(message: 'Saving Virtual Room and setting up geofence...')
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ROOM PARAMETERS',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Room Name',
                        hintText: 'e.g. Lab 403, Seminar Hall A',
                        prefixIcon: Icon(Icons.room_rounded),
                      ),
                      validator: (v) => (v == null || v.isEmpty) ? 'Room name is required' : null,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _buildingController,
                            decoration: const InputDecoration(
                              labelText: 'Building',
                              hintText: 'e.g. CS Block',
                              prefixIcon: Icon(Icons.apartment_rounded),
                            ),
                            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: TextFormField(
                            controller: _floorController,
                            decoration: const InputDecoration(
                              labelText: 'Floor Number',
                              hintText: 'e.g. 4',
                              prefixIcon: Icon(Icons.layers_outlined),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _deptController,
                            decoration: const InputDecoration(
                              labelText: 'Department',
                              hintText: 'e.g. CSE, ECE',
                              prefixIcon: Icon(Icons.school_rounded),
                            ),
                            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: TextFormField(
                            controller: _capacityController,
                            decoration: const InputDecoration(
                              labelText: 'Capacity',
                              hintText: 'e.g. 60',
                              prefixIcon: Icon(Icons.people_alt_rounded),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                    const Text(
                      'PHYSICAL GPS CORNERS (EXACTLY 4)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Walk to each corner of the room in chronological sequence and capture the high-precision GPS coordinate directly from your device.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Capture buttons grid
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.7,
                      ),
                      itemCount: 4,
                      itemBuilder: (context, index) {
                        final cornerIdx = index + 1;
                        final corner = captureState.corners[index];
                        final isCapturingThis = captureState.isCapturing && captureState.statusMessage.contains('corner $cornerIdx');

                        return _CornerCaptureButton(
                          cornerIndex: cornerIdx,
                          corner: corner,
                          isCapturing: captureState.isCapturing,
                          isCapturingThis: isCapturingThis,
                          readingCount: captureState.readingCount,
                          onPressed: () => _triggerCapture(cornerIdx),
                        );
                      },
                    ),

                    if (captureState.isCapturing) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.primaryLight.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                captureState.statusMessage,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryLight,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Room polygon preview canvas section
                    if (allCornersCaptured) ...[
                      const SizedBox(height: 28),
                      const Text(
                        'POLYGON FOOTPRINT PREVIEW',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        height: 220,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.03),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.borderColor),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Stack(
                            children: [
                              CustomPaint(
                                size: Size.infinite,
                                painter: _PolygonPreviewPainter(
                                  corners: captureState.corners.whereType<RoomCornerModel>().toList(),
                                ),
                              ),
                              Positioned(
                                bottom: 12,
                                right: 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.7),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'Scale Normalized',
                                    style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 40),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryLight,
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _saveRoom,
                      child: Text(
                        isEdit ? 'Save Changes' : 'Register Virtual Room',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
    );
  }
}

class _CornerCaptureButton extends StatelessWidget {
  final int cornerIndex;
  final RoomCornerModel? corner;
  final bool isCapturing;
  final bool isCapturingThis;
  final int readingCount;
  final VoidCallback onPressed;

  const _CornerCaptureButton({
    required this.cornerIndex,
    required this.corner,
    required this.isCapturing,
    required this.isCapturingThis,
    required this.readingCount,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final hasData = corner != null;

    return InkWell(
      onTap: isCapturing ? null : onPressed,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isCapturingThis
              ? AppColors.primaryLight.withOpacity(0.05)
              : (hasData ? AppColors.success.withOpacity(0.04) : Colors.transparent),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isCapturingThis
                ? AppColors.primaryLight
                : (hasData ? AppColors.success.withOpacity(0.5) : AppColors.borderColor),
            width: isCapturingThis ? 2.0 : 1.0,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Corner $cornerIndex',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isCapturingThis
                        ? AppColors.primaryLight
                        : (hasData ? AppColors.success : AppColors.textPrimary),
                  ),
                ),
                Icon(
                  hasData
                      ? Icons.check_circle_rounded
                      : (isCapturingThis ? Icons.hourglass_top_rounded : Icons.gps_fixed_rounded),
                  size: 18,
                  color: isCapturingThis
                      ? AppColors.primaryLight
                      : (hasData ? AppColors.success : AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (isCapturingThis)
              Text(
                'Reading $readingCount of 3...',
                style: const TextStyle(fontSize: 10, color: AppColors.primaryLight, fontWeight: FontWeight.bold),
              )
            else if (hasData)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Lat: ${corner!.latitude.toStringAsFixed(6)}',
                    style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontFamily: 'monospace'),
                    maxLines: 1,
                  ),
                  Text(
                    'Lng: ${corner!.longitude.toStringAsFixed(6)}',
                    style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontFamily: 'monospace'),
                    maxLines: 1,
                  ),
                ],
              )
            else
              const Text(
                'Tap to Capture',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
              ),
          ],
        ),
      ),
    );
  }
}

// Gorgeous Relative Coordinate Polygon Canvas custom painter
class _PolygonPreviewPainter extends CustomPainter {
  final List<RoomCornerModel> corners;

  _PolygonPreviewPainter({required this.corners});

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length < 3) return;

    // Find bounding box
    double minLat = corners.map((c) => c.latitude).reduce((a, b) => a < b ? a : b);
    double maxLat = corners.map((c) => c.latitude).reduce((a, b) => a > b ? a : b);
    double minLng = corners.map((c) => c.longitude).reduce((a, b) => a < b ? a : b);
    double maxLng = corners.map((c) => c.longitude).reduce((a, b) => a > b ? a : b);

    double latSpan = maxLat - minLat;
    double lngSpan = maxLng - minLng;

    // Avoid division by zero
    if (latSpan == 0.0) latSpan = 0.0001;
    if (lngSpan == 0.0) lngSpan = 0.0001;

    // Add padding inside canvas
    const double padding = 40.0;
    final double drawW = size.width - (padding * 2);
    final double drawH = size.height - (padding * 2);

    // Keep aspect ratio
    final double maxSpan = latSpan > lngSpan ? latSpan : lngSpan;

    // Project corners to screen offsets
    final List<Offset> points = corners.map((c) {
      // Scale coordinates to fit centered inside canvas
      double x = padding + (((c.longitude - minLng) / maxSpan) * drawW);
      // Flip y since north is up, but screen y grows downwards
      double y = padding + (((maxLat - c.latitude) / maxSpan) * drawH);
      
      // Center the polygon horizontally/vertically in case bounding box is not square
      if (latSpan > lngSpan) {
        double offset = (drawW - ((lngSpan / maxSpan) * drawW)) / 2.0;
        x += offset;
      } else {
        double offset = (drawH - ((latSpan / maxSpan) * drawH)) / 2.0;
        y += offset;
      }
      return Offset(x, y);
    }).toList();

    // 1. Draw solid translucent filled polygon
    final fillPaint = Paint()
      ..color = AppColors.success.withOpacity(0.12)
      ..style = PaintingStyle.fill;

    final path = Path()..moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    path.close();
    canvas.drawPath(path, fillPaint);

    // 2. Draw polygon outline
    final strokePaint = Paint()
      ..color = AppColors.success
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, strokePaint);

    // 3. Draw vertices (corners) and text labels
    final vertexPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      // Draw vertex outer circle border
      canvas.drawCircle(p, 8.0, Paint()..color = AppColors.success);
      // Draw vertex filled circle
      canvas.drawCircle(p, 6.0, vertexPaint);
      
      // Draw beautiful text label
      final textSpan = TextSpan(
        text: 'C${i + 1}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9.0,
          fontWeight: FontWeight.bold,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      
      // Draw centered inside circle
      textPainter.paint(canvas, Offset(p.dx - (textPainter.width / 2), p.dy - (textPainter.height / 2)));
    }
  }

  @override
  bool shouldRepaint(covariant _PolygonPreviewPainter oldDelegate) {
    return oldDelegate.corners != corners;
  }
}
