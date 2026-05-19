import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/auth_provider.dart';
import 'providers/virtual_room_providers.dart';
import 'room_capture_overlay.dart';
import 'room_preview_widget.dart';
import 'models/virtual_room_model.dart';

class AddEditRoomScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? existingRoom;

  const AddEditRoomScreen({Key? key, this.existingRoom}) : super(key: key);

  @override
  ConsumerState<AddEditRoomScreen> createState() => _AddEditRoomScreenState();
}

class _AddEditRoomScreenState extends ConsumerState<AddEditRoomScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _buildingController;
  late final TextEditingController _departmentController;
  late final TextEditingController _floorController;
  late final TextEditingController _capacityController;

  List<RoomCornerReading> _capturedCorners = [];
  int? _capturingCornerIndex;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existingRoom?['name']?.toString() ?? '');
    _buildingController = TextEditingController(text: widget.existingRoom?['building']?.toString() ?? '');
    _departmentController = TextEditingController(text: widget.existingRoom?['department']?.toString() ?? '');
    _floorController = TextEditingController(text: widget.existingRoom?['floor_number']?.toString() ?? '0');
    _capacityController = TextEditingController(text: widget.existingRoom?['capacity']?.toString() ?? '60');

    // Parse existing corners if editing
    if (widget.existingRoom != null && widget.existingRoom!['corners'] is List) {
      final list = widget.existingRoom!['corners'] as List;
      _capturedCorners = list.map((e) {
        final m = e as Map<String, dynamic>;
        return RoomCornerReading(
          latitude: (m['latitude'] as num? ?? m['lat'] as num? ?? 0.0).toDouble(),
          longitude: (m['longitude'] as num? ?? m['lng'] as num? ?? 0.0).toDouble(),
          altitude: (m['altitude'] as num? ?? m['alt'] as num? ?? 0.0).toDouble(),
          heading: (m['heading'] as num? ?? 0.0).toDouble(),
          accuracy: (m['accuracy'] as num? ?? 0.0).toDouble(),
        );
      }).toList();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _buildingController.dispose();
    _departmentController.dispose();
    _floorController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    if (_capturedCorners.length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please capture exactly 4 corners to establish the room polygon.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    // Build coordinates payload
    final cornerCoords = _capturedCorners.map((e) => {
      'lat': e.latitude,
      'lng': e.longitude,
      'alt': e.altitude,
      'heading': e.heading,
      'accuracy': e.accuracy,
    }).toList();

    final authState = ref.read(authProvider);
    String? collegeId;
    if (authState is AuthSuccess) {
      collegeId = authState.user.collegeId;
    }

    final payload = {
      'name': _nameController.text.trim(),
      'building': _buildingController.text.trim(),
      'department': _departmentController.text.trim(),
      'floor_number': int.tryParse(_floorController.text) ?? 0,
      'capacity': int.tryParse(_capacityController.text) ?? 60,
      'corner_coordinates': cornerCoords,
      if (collegeId != null) 'college': collegeId,
    };

    bool success = false;
    final notifier = ref.read(virtualRoomsProvider.notifier);

    if (widget.existingRoom != null) {
      final id = widget.existingRoom!['id'].toString();
      success = await notifier.editRoom(id, payload);
    } else {
      success = await notifier.addRoom(payload);
    }

    setState(() => _isSaving = false);

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.existingRoom != null
                ? 'Virtual room updated successfully.'
                : 'Virtual room created successfully.'),
            backgroundColor: Colors.teal,
          ),
        );
        context.pop();
      } else {
        final state = ref.read(virtualRoomsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(state.error ?? 'Failed to save virtual room.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isEdit = widget.existingRoom != null;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: isDark ? const Color(0xFF0B0F19) : Colors.grey.shade50,
          appBar: AppBar(
            title: Text(isEdit ? 'Edit Virtual Room' : 'Create Virtual Room'),
            actions: [
              IconButton(
                icon: const Icon(Icons.check_rounded),
                onPressed: _isSaving ? null : _submitForm,
              )
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Form Fields Section
                  _buildSectionHeader(theme, 'Room Identity Details'),
                  const SizedBox(height: 12),
                  _buildFormCard(isDark, [
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Room Name (e.g. Lab 4B)',
                        prefixIcon: Icon(Icons.sensor_door_rounded),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Room name is required' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _buildingController,
                      decoration: const InputDecoration(
                        labelText: 'Building Name',
                        prefixIcon: Icon(Icons.apartment_rounded),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Building name is required' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _departmentController,
                      decoration: const InputDecoration(
                        labelText: 'Department Name',
                        prefixIcon: Icon(Icons.work_rounded),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Department is required' : null,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _floorController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Floor Number',
                              prefixIcon: Icon(Icons.layers_rounded),
                            ),
                            validator: (v) => v == null || int.tryParse(v) == null ? 'Enter valid number' : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _capacityController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Max Capacity',
                              prefixIcon: Icon(Icons.people_rounded),
                            ),
                            validator: (v) => v == null || int.tryParse(v) == null ? 'Enter valid number' : null,
                          ),
                        ),
                      ],
                    ),
                  ]),
                  const SizedBox(height: 28),

                  // GPS Polygon Section
                  _buildSectionHeader(theme, 'GPS Polygon Boundary'),
                  const SizedBox(height: 8),
                  Text(
                    'Walk around classroom corners and capture exactly 4 boundaries.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.disabledColor),
                  ),
                  const SizedBox(height: 16),

                  // 2D Preview canvas
                  RoomPreviewWidget(corners: _capturedCorners),
                  const SizedBox(height: 20),

                  // Corner Grid Cards
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.5,
                    ),
                    itemCount: 4,
                    itemBuilder: (context, idx) {
                      final cornerIdx = idx + 1;
                      final isCaptured = _capturedCorners.length >= cornerIdx;
                      final reading = isCaptured ? _capturedCorners[idx] : null;

                      return Container(
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isCaptured
                                ? Colors.teal.withOpacity(0.3)
                                : theme.primaryColor.withOpacity(0.1),
                            width: 1.5,
                          ),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => setState(() => _capturingCornerIndex = cornerIdx),
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isCaptured ? Colors.teal.withOpacity(0.12) : theme.primaryColor.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          'Corner $cornerIdx',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: isCaptured ? Colors.teal : theme.primaryColor,
                                          ),
                                        ),
                                      ),
                                      const Spacer(),
                                      Icon(
                                        isCaptured ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                                        color: isCaptured ? Colors.teal : theme.primaryColor.withOpacity(0.5),
                                        size: 20,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  if (isCaptured && reading != null) ...[
                                    Text(
                                      'Lat: ${reading.latitude.toStringAsFixed(6)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 10, fontWeight: FontWeight.w600),
                                    ),
                                    Text(
                                      'Lng: ${reading.longitude.toStringAsFixed(6)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 10, fontWeight: FontWeight.w600),
                                    ),
                                  ] else
                                    Text(
                                      'Tap to capture GPS',
                                      style: theme.textTheme.bodySmall?.copyWith(color: theme.disabledColor, fontSize: 10),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 32),

                  // Bottom Save Action
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _submitForm,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        isEdit ? 'Update Virtual Room' : 'Create Virtual Room',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),

        // Corner Capture Modal Overlay
        if (_capturingCornerIndex != null)
          Positioned.fill(
            child: RoomCaptureOverlay(
              cornerIndex: _capturingCornerIndex!,
              allCapturedCorners: List.unmodifiable(_capturedCorners),
              onCancel: () => setState(() => _capturingCornerIndex = null),
              onCaptured: (reading) {
                final capturedIdx = _capturingCornerIndex!;
                setState(() {
                  final idx = capturedIdx - 1;
                  if (_capturedCorners.length > idx) {
                    _capturedCorners[idx] = reading;
                  } else {
                    _capturedCorners.add(reading);
                  }
                  _capturingCornerIndex = null;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Corner $capturedIdx captured successfully'),
                    backgroundColor: Colors.teal,
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String text) {
    return Text(
      text,
      style: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: theme.primaryColor,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildFormCard(bool isDark, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: children,
      ),
    );
  }
}