// presentation/screens/create_virtual_room_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// High-fidelity UI configuration form for Virtual Room creation & edit in light theme.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/layout/app_layout.dart';
import '../../../../core/utils/form_validators.dart';
import '../../data/models/corner_data.dart';
import '../widgets/room_capture_overlay.dart';
import '../providers/virtual_room_providers.dart';
import '../painters/room_preview_painter.dart';

class CreateVirtualRoomScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? existingRoom;
  const CreateVirtualRoomScreen({super.key, this.existingRoom});

  @override
  ConsumerState<CreateVirtualRoomScreen> createState() => _CreateVirtualRoomScreenState();
}

class _CreateVirtualRoomScreenState extends ConsumerState<CreateVirtualRoomScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameCtrl;
  late TextEditingController _buildingCtrl;
  late TextEditingController _deptCtrl;
  late TextEditingController _capacityCtrl;
  late TextEditingController _latCtrl;
  late TextEditingController _lngCtrl;

  int _floor = 0;
  double _radius = 30.0;
  double _minAlt = 0.0;
  double _maxAlt = 50.0;
  bool _fetchingGps = false;
  List<CornerData> _capturedCorners = [];

  bool get _isEdit => widget.existingRoom != null;

  @override
  void initState() {
    super.initState();
    final r = widget.existingRoom;
    _nameCtrl     = TextEditingController(text: r?['name'] ?? '');
    _buildingCtrl = TextEditingController(text: r?['building'] ?? '');
    _deptCtrl     = TextEditingController(text: r?['department'] ?? '');
    _capacityCtrl = TextEditingController(text: r?['capacity']?.toString() ?? '60');
    _latCtrl      = TextEditingController(text: r?['center_lat']?.toString() ?? '');
    _lngCtrl      = TextEditingController(text: r?['center_lng']?.toString() ?? '');

    if (r != null) {
      _floor  = r['floor_number'] as int? ?? 0;
      _radius = (r['radius_meters'] as num?)?.toDouble() ?? 30.0;
      _minAlt = (r['min_altitude'] as num?)?.toDouble() ?? 0.0;
      _maxAlt = (r['max_altitude'] as num?)?.toDouble() ?? 50.0;
      
      if (r['corner_coordinates'] != null) {
        _capturedCorners = (r['corner_coordinates'] as List)
            .map((c) => CornerData.fromJson(Map<String, dynamic>.from(c as Map)))
            .toList();
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _buildingCtrl.dispose();
    _deptCtrl.dispose();
    _capacityCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchCurrentLocation() async {
    setState(() => _fetchingGps = true);
    try {
      bool enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        _showError('Location services are disabled.');
        return;
      }
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        _showError('Location permission denied.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
      setState(() {
        _latCtrl.text = pos.latitude.toStringAsFixed(7);
        _lngCtrl.text = pos.longitude.toStringAsFixed(7);
      });
      _showSuccess('GPS coordinates resolved!');
    } catch (e) {
      _showError('Failed to capture GPS: $e');
    } finally {
      if (mounted) setState(() => _fetchingGps = false);
    }
  }

  void _showError(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.danger),
      );
    }
  }

  void _showSuccess(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.success),
      );
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final lat = double.tryParse(_latCtrl.text.trim());
    final lng = double.tryParse(_lngCtrl.text.trim());

    if (lat == null || lng == null) {
      _showError('Invalid latitude or longitude values.');
      return;
    }
    if (_maxAlt <= _minAlt) {
      _showError('Max altitude must be greater than min altitude.');
      return;
    }

    final data = {
      'name':          _nameCtrl.text.trim(),
      'building':      _buildingCtrl.text.trim(),
      'department':    _deptCtrl.text.trim(),
      'capacity':      int.tryParse(_capacityCtrl.text) ?? 60,
      'floor_number':  _floor,
      'center_lat':    lat,
      'center_lng':    lng,
      'radius_meters': _radius,
      'min_altitude':  _minAlt,
      'max_altitude':  _maxAlt,
      'use_polygon':   _capturedCorners.isNotEmpty,
      'corner_coordinates': _capturedCorners.isNotEmpty 
          ? _capturedCorners.map((c) => c.toJson()).toList() 
          : null,
    };

    bool success;
    if (_isEdit) {
      success = await ref.read(roomCrudProvider.notifier).updateRoom(widget.existingRoom!['id'].toString(), data);
    } else {
      success = await ref.read(roomCrudProvider.notifier).createRoom(data);
    }

    if (!mounted) return;

    final state = ref.read(roomCrudProvider);
    final msg = state is RoomCrudSuccess
        ? state.message
        : state is RoomCrudError
            ? state.message
            : 'Operational failure';

    _showSuccess(msg);

    if (success) {
      ref.read(roomCrudProvider.notifier).reset();
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final crudState = ref.watch(roomCrudProvider);
    final isLoading = crudState is RoomCrudLoading;

    return AppLayout(
      title: _isEdit ? 'Reconfigure Spatial Room' : 'Create Spatial Room',
      child: Container(
        color: AppColors.bgPrimary,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(Icons.info_outline_rounded, 'IDENTITY DETAILS'),
                _buildGlassInput(
                  controller: _nameCtrl,
                  label: 'Classroom Name',
                  hint: 'e.g. Physics Seminar Lab',
                  icon: Icons.meeting_room_outlined,
                  validator: (v) => FormValidators.minLength(v, 2, 'Classroom name'),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildGlassInput(
                        controller: _buildingCtrl,
                        label: 'Building',
                        hint: 'Science Block C',
                        icon: Icons.apartment_rounded,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildFloorPicker(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildGlassInput(
                        controller: _deptCtrl,
                        label: 'Department',
                        hint: 'CSE',
                        icon: Icons.school_outlined,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildGlassInput(
                        controller: _capacityCtrl,
                        label: 'Capacity',
                        hint: '60',
                        icon: Icons.people_outline_rounded,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                _buildHeader(Icons.spatial_tracking_rounded, '3D GEOMETRY CAPTURE'),
                _buildSpatialCaptureCard(),
                const SizedBox(height: 32),

                _buildHeader(Icons.radar_rounded, 'FALLBACK GEO-FENCING'),
                _buildRadiusControl(),
                const SizedBox(height: 16),
                _buildAltitudeControl(),
                const SizedBox(height: 16),
                _buildManualGpsCard(),
                const SizedBox(height: 40),

                if (isLoading)
                  const Center(child: CircularProgressIndicator(color: AppColors.primary))
                else
                  ElevatedButton.icon(
                    onPressed: _submit,
                    icon: Icon(_isEdit ? Icons.save_rounded : Icons.add_circle_outline_rounded, color: Colors.white),
                    label: Text(_isEdit ? 'UPDATE SPATIAL GEOMETRY' : 'INITIALIZE SPATIAL ROOM', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 56),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 4,
                    ),
                  ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassInput({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderColor),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        validator: validator,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.black26, fontSize: 13),
          prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 18),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildFloorPicker() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderColor),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.layers_outlined, color: AppColors.textSecondary, size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('FLOOR', style: TextStyle(color: AppColors.textSecondary, fontSize: 9)),
              Text('$_floor', style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
          const Spacer(),
          Column(
            children: [
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_up_rounded, color: AppColors.primary, size: 18),
                onPressed: () => setState(() => _floor++),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.primary, size: 18),
                onPressed: () => setState(() => _floor > 0 ? _floor-- : 0),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSpatialCaptureCard() {
    final hasCorners = _capturedCorners.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderColor),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 6, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        children: [
          if (!hasCorners) ...[
            Icon(Icons.spatial_audio_rounded, color: AppColors.primary.withOpacity(0.4), size: 40),
            const SizedBox(height: 12),
            const Text(
              'No physical footprint captured.',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 6),
            const Text(
              'Capture classroom corner telemetry using the integrated sensors to generate precise spatial vectors.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11, height: 1.4),
            ),
          ] else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('SPATIAL FOOTPRINT', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13)),
                Text('${_capturedCorners.length}/4 CORNERS RESOLVED', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              height: 140,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.bgSecondary,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.borderColor),
              ),
              child: CustomPaint(
                painter: RoomPreviewPainter(
                  corners: _capturedCorners.map((c) => {'x': c.heading, 'y': c.heading * 0.8}).toList(), // placeholder mock scaling on coordinates
                  headingAngle: '0.0',
                  length: 10.0,
                  width: 10.0,
                  area: 100.0,
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => RoomCaptureOverlay(
                    onCaptureComplete: (corners) {
                      setState(() {
                        _capturedCorners = corners;
                        if (corners.isNotEmpty) {
                          _latCtrl.text = corners[0].lat.toStringAsFixed(7);
                          _lngCtrl.text = corners[0].lng.toStringAsFixed(7);
                          _minAlt = corners.map((c) => c.alt).reduce((a, b) => a < b ? a : b) - 2.0;
                          _maxAlt = corners.map((c) => c.alt).reduce((a, b) => a > b ? a : b) + 3.0;
                        }
                      });
                    },
                  ),
                ),
              );
            },
            icon: Icon(hasCorners ? Icons.refresh_rounded : Icons.spatial_tracking_rounded),
            label: Text(hasCorners ? 'RE-CAPTURE CORNERS' : 'START SPATIAL CAPTURE'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRadiusControl() {
    return _buildGlassContainer(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Legacy Geofence Radius', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              Text('${_radius.round()} meters', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
          Slider(
            value: _radius,
            min: 5,
            max: 150,
            divisions: 29,
            activeColor: AppColors.primary,
            inactiveColor: AppColors.borderColor,
            onChanged: (v) => setState(() => _radius = v),
          ),
        ],
      ),
    );
  }

  Widget _buildAltitudeControl() {
    return _buildGlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Altitude Ceiling Threshold (relative)', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('MIN ALTITUDE', style: TextStyle(color: AppColors.textSecondary, fontSize: 9)),
                    const SizedBox(height: 4),
                    Text('${_minAlt.round()}m', style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_left_rounded, color: AppColors.primary),
                onPressed: () => setState(() => _minAlt--),
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_right_rounded, color: AppColors.primary),
                onPressed: () => setState(() => _minAlt++),
              ),
              const Spacer(),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('MAX ALTITUDE', style: TextStyle(color: AppColors.textSecondary, fontSize: 9)),
                    const SizedBox(height: 4),
                    Text('${_maxAlt.round()}m', style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_left_rounded, color: AppColors.primary),
                onPressed: () => setState(() => _maxAlt--),
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_right_rounded, color: AppColors.primary),
                onPressed: () => setState(() => _maxAlt++),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildManualGpsCard() {
    return _buildGlassContainer(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Anchor Latitude / Longitude', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              if (_fetchingGps)
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
              else
                IconButton(
                  icon: const Icon(Icons.gps_fixed_rounded, color: AppColors.primary, size: 18),
                  onPressed: _fetchCurrentLocation,
                  tooltip: 'Resolve GPS coordinates',
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _latCtrl,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                  decoration: const InputDecoration(labelText: 'Latitude', labelStyle: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _lngCtrl,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                  decoration: const InputDecoration(labelText: 'Longitude', labelStyle: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGlassContainer({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderColor),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: child,
    );
  }
}
