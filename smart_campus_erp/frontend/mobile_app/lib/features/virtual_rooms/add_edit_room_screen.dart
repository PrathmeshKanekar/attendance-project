import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/layout/app_layout.dart';
import 'virtual_room_providers.dart';

class AddEditRoomScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? existingRoom; // null = create, else = edit
  const AddEditRoomScreen({super.key, this.existingRoom});

  @override
  ConsumerState<AddEditRoomScreen> createState() =>
      _AddEditRoomScreenState();
}

class _AddEditRoomScreenState extends ConsumerState<AddEditRoomScreen> {
  final _formKey = GlobalKey<FormState>();

  // ── Controllers ──────────────────────────────────────────
  late TextEditingController _nameCtrl;
  late TextEditingController _buildingCtrl;
  late TextEditingController _latCtrl;
  late TextEditingController _lngCtrl;

  int    _floor    = 0;
  double _radius   = 30.0;
  double _minAlt   = 0.0;
  double _maxAlt   = 50.0;
  bool   _fetchingGps = false;

  bool get _isEdit => widget.existingRoom != null;

  @override
  void initState() {
    super.initState();
    final r = widget.existingRoom;
    _nameCtrl     = TextEditingController(text: r?['name']     ?? '');
    _buildingCtrl = TextEditingController(text: r?['building'] ?? '');
    _latCtrl      = TextEditingController(
      text: r?['center_lat']?.toString() ?? '',
    );
    _lngCtrl      = TextEditingController(
      text: r?['center_lng']?.toString() ?? '',
    );
    if (r != null) {
      _floor  = r['floor_number']  as int?    ?? 0;
      _radius = (r['radius_meters'] as num?)?.toDouble() ?? 30.0;
      _minAlt = (r['min_altitude']  as num?)?.toDouble() ?? 0.0;
      _maxAlt = (r['max_altitude']  as num?)?.toDouble() ?? 50.0;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _buildingCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    super.dispose();
  }

  // ── Auto-fill GPS from device ─────────────────────────────
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
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _showError('Location permission denied.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
      setState(() {
        _latCtrl.text = pos.latitude.toStringAsFixed(7);
        _lngCtrl.text = pos.longitude.toStringAsFixed(7);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content        : Text('GPS coordinates captured!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      _showError('Failed to get location: $e');
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

  // ── Submit form ───────────────────────────────────────────
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
      'name'          : _nameCtrl.text.trim(),
      'building'      : _buildingCtrl.text.trim(),
      'floor_number'  : _floor,
      'center_lat'    : lat,
      'center_lng'    : lng,
      'radius_meters' : _radius,
      'min_altitude'  : _minAlt,
      'max_altitude'  : _maxAlt,
    };

    bool success;
    if (_isEdit) {
      success = await ref
          .read(roomCrudProvider.notifier)
          .updateRoom(widget.existingRoom!['id'].toString(), data);
    } else {
      success = await ref
          .read(roomCrudProvider.notifier)
          .createRoom(data);
    }

    if (!mounted) return;

    final state = ref.read(roomCrudProvider);
    final msg   = state is RoomCrudSuccess
        ? state.message
        : state is RoomCrudError
            ? state.message
            : '';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content        : Text(msg),
        backgroundColor: success ? AppColors.success : AppColors.danger,
      ),
    );

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
      title: _isEdit ? 'Edit Room' : 'Add Virtual Room',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child  : Form(
          key : _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ── Section: Basic Info ──────────────────────
              const _SectionHeader(label: 'Basic Information'),

              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText : 'Room Name',
                  hintText  : 'e.g. Classroom 301, Lab A',
                  prefixIcon: Icon(Icons.sensor_door_rounded),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Room name is required' : null,
              ),

              const SizedBox(height: 14),

              TextFormField(
                controller: _buildingCtrl,
                decoration: const InputDecoration(
                  labelText : 'Building Name',
                  hintText  : 'e.g. A Block, Main Building',
                  prefixIcon: Icon(Icons.business_rounded),
                ),
              ),

              const SizedBox(height: 14),

              // Floor number picker
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Floor Number',
                      style: TextStyle(
                        fontSize: 14,
                        color   : AppColors.textSecondary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon     : const Icon(Icons.remove_circle_outline),
                    onPressed: _floor > 0
                        ? () => setState(() => _floor--)
                        : null,
                    color    : AppColors.primaryLight,
                  ),
                  Container(
                    width  : 48,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color       : AppColors.bgSecondary,
                      borderRadius: BorderRadius.circular(8),
                      border      : Border.all(color: AppColors.borderColor),
                    ),
                    child: Text(
                      '$_floor',
                      textAlign: TextAlign.center,
                      style    : const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize  : 16,
                      ),
                    ),
                  ),
                  IconButton(
                    icon     : const Icon(Icons.add_circle_outline),
                    onPressed: _floor < 20
                        ? () => setState(() => _floor++)
                        : null,
                    color    : AppColors.primaryLight,
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // ── Section: GPS Coordinates ─────────────────
              const _SectionHeader(label: 'GPS Coordinates (Center of Room)'),

              // Auto-fill button
              Container(
                width  : double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color       : AppColors.primaryLight.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                  border      : Border.all(
                    color: AppColors.primaryLight.withOpacity(0.25),
                  ),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.gps_fixed_rounded,
                      color: AppColors.primaryLight,
                      size : 32,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Go to the center of the classroom,\n'
                      'then tap to capture your current location.',
                      textAlign: TextAlign.center,
                      style    : TextStyle(
                        color  : AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style    : OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primaryLight,
                          side           : const BorderSide(
                            color: AppColors.primaryLight,
                          ),
                          minimumSize: const Size(0, 46),
                        ),
                        onPressed: _fetchingGps ? null : _fetchCurrentLocation,
                        icon : _fetchingGps
                            ? const SizedBox(
                                width : 16, height: 16,
                                child : CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor : AlwaysStoppedAnimation(
                                    AppColors.primaryLight,
                                  ),
                                ),
                              )
                            : const Icon(Icons.my_location_rounded),
                        label: Text(
                          _fetchingGps
                              ? 'Getting location...'
                              : 'Use My Current Location',
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Manual lat/lng fields
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller : _latCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true,
                      ),
                      decoration : const InputDecoration(
                        labelText : 'Latitude',
                        hintText  : '18.5204300',
                        prefixIcon: Icon(Icons.place_rounded),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Required';
                        }
                        final lat = double.tryParse(v.trim());
                        if (lat == null) return 'Invalid number';
                        if (lat < -90 || lat > 90) return '-90 to 90';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller : _lngCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true,
                      ),
                      decoration : const InputDecoration(
                        labelText : 'Longitude',
                        hintText  : '73.8567400',
                        prefixIcon: Icon(Icons.place_rounded),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Required';
                        }
                        final lng = double.tryParse(v.trim());
                        if (lng == null) return 'Invalid number';
                        if (lng < -180 || lng > 180) return '-180 to 180';
                        return null;
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // ── Section: Geo Fence ───────────────────────
              const _SectionHeader(label: 'Geo-Fence Settings'),

              // Radius slider
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Boundary Radius',
                    style: TextStyle(
                      fontSize: 14,
                      color   : AppColors.textSecondary,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color       : AppColors.primaryLight.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_radius.round()}m',
                      style: const TextStyle(
                        color    : AppColors.primaryLight,
                        fontWeight: FontWeight.w700,
                        fontSize  : 15,
                      ),
                    ),
                  ),
                ],
              ),
              Slider(
                value      : _radius,
                min        : 10,
                max        : 200,
                divisions  : 38,
                label      : '${_radius.round()}m',
                activeColor: AppColors.primaryLight,
                onChanged  : (v) => setState(() => _radius = v),
              ),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('10m', style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 11,
                  )),
                  Text('Slide to set boundary radius', style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 11,
                  )),
                  Text('200m', style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 11,
                  )),
                ],
              ),

              const SizedBox(height: 20),

              // Altitude range
              const _SectionHeader(label: 'Altitude Range (meters)'),
              const Text(
                'Used for multi-floor buildings. Students must be '
                'within this altitude range to mark attendance.',
                style: TextStyle(
                  color  : AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Min Altitude', style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary,
                        )),
                        const SizedBox(height: 6),
                        Slider(
                          value      : _minAlt,
                          min        : -10,
                          max        : 100,
                          divisions  : 110,
                          label      : '${_minAlt.round()}m',
                          activeColor: AppColors.success,
                          onChanged  : (v) {
                            if (v < _maxAlt) {
                              setState(() => _minAlt = v);
                            }
                          },
                        ),
                        Center(child: Text(
                          '${_minAlt.round()}m',
                          style: const TextStyle(
                            color: AppColors.success, fontWeight: FontWeight.bold,
                          ),
                        )),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Max Altitude', style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary,
                        )),
                        const SizedBox(height: 6),
                        Slider(
                          value      : _maxAlt,
                          min        : 0,
                          max        : 200,
                          divisions  : 200,
                          label      : '${_maxAlt.round()}m',
                          activeColor: AppColors.danger,
                          onChanged  : (v) {
                            if (v > _minAlt) {
                              setState(() => _maxAlt = v);
                            }
                          },
                        ),
                        Center(child: Text(
                          '${_maxAlt.round()}m',
                          style: const TextStyle(
                            color: AppColors.danger, fontWeight: FontWeight.bold,
                          ),
                        )),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // ── Preview card ─────────────────────────────
              if (_latCtrl.text.isNotEmpty && _lngCtrl.text.isNotEmpty)
                Container(
                  padding   : const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color       : AppColors.success.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border      : Border.all(
                      color: AppColors.success.withOpacity(0.25),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Room Preview', style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color     : AppColors.textPrimary,
                      )),
                      const SizedBox(height: 8),
                      _PreviewRow('Name',    _nameCtrl.text.trim()),
                      _PreviewRow('Building', _buildingCtrl.text.trim()),
                      _PreviewRow('Floor',    'Floor $_floor'),
                      _PreviewRow('Center',   '${_latCtrl.text}, ${_lngCtrl.text}'),
                      _PreviewRow('Radius',   '${_radius.round()}m'),
                      _PreviewRow('Altitude', '${_minAlt.round()}m – ${_maxAlt.round()}m'),
                    ],
                  ),
                ),

              const SizedBox(height: 24),

              // ── Submit ───────────────────────────────────
              isLoading
                  ? const Center(child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation(AppColors.primaryLight),
                  ))
                  : ElevatedButton.icon(
                      onPressed: _submit,
                      icon     : Icon(
                        _isEdit
                            ? Icons.save_rounded
                            : Icons.add_location_rounded,
                      ),
                      label: Text(
                        _isEdit ? 'Save Changes' : 'Create Virtual Room',
                      ),
                    ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Section header ─────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child  : Text(
        label,
        style: const TextStyle(
          fontSize  : 15,
          fontWeight: FontWeight.w700,
          color     : AppColors.textPrimary,
        ),
      ),
    );
  }
}

// ── Preview row ────────────────────────────────────────────
class _PreviewRow extends StatelessWidget {
  final String label, value;
  const _PreviewRow(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child  : Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: const TextStyle(
              color: AppColors.textSecondary, fontSize: 12,
            )),
          ),
          Expanded(child: Text(value, style: const TextStyle(
            color: AppColors.textPrimary, fontSize: 12,
            fontWeight: FontWeight.w600,
          ))),
        ],
      ),
    );
  }
}
