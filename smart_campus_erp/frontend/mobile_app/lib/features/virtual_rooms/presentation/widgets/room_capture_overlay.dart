// presentation/widgets/room_capture_overlay.dart
// ─────────────────────────────────────────────────────────────────────────────
// Interactive sequential corner telemetry overlay.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/constants/app_colors.dart';
import '../../data/models/corner_data.dart';

class RoomCaptureOverlay extends StatefulWidget {
  final Function(List<CornerData>) onCaptureComplete;
  const RoomCaptureOverlay({super.key, required this.onCaptureComplete});

  @override
  State<RoomCaptureOverlay> createState() => _RoomCaptureOverlayState();
}

class _RoomCaptureOverlayState extends State<RoomCaptureOverlay> {
  final List<CornerData> _captured = [];
  bool _fetching = false;
  int _current = 1;

  Future<void> _captureCurrentCorner() async {
    setState(() => _fetching = true);
    try {
      bool enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        _showSnack('Location services are disabled.', AppColors.danger);
        return;
      }
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        _showSnack('Location permission denied.', AppColors.danger);
        return;
      }

      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
      
      final corner = CornerData(
        lat: pos.latitude,
        lng: pos.longitude,
        alt: pos.altitude,
        accuracy: pos.accuracy,
        altitudeAccuracy: 3.0,
        heading: pos.heading,
      );

      setState(() {
        _captured.add(corner);
        if (_current < 4) {
          _current++;
        } else {
          // Finalized
          widget.onCaptureComplete(_captured);
          Navigator.pop(context);
        }
      });
      _showSnack('Corner $_current captured!', AppColors.success);
    } catch (e) {
      _showSnack('Capture failed: $e', AppColors.danger);
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  void _showSnack(String msg, Color bg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: bg, duration: const Duration(seconds: 1)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.85),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildHeader(),
              _buildProgressLayout(),
              _buildActionControls(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'SPATIAL SURVEY TELEMETRY',
              style: TextStyle(color: AppColors.primaryLight, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white60),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Please stand exactly at each physical corner of the classroom and capture coordinates in clockwise order.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
        ),
      ],
    );
  }

  Widget _buildProgressLayout() {
    return Column(
      children: [
        Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primaryLight.withOpacity(0.04),
            border: Border.all(color: AppColors.primaryLight.withOpacity(0.12), width: 2),
            boxShadow: [
              BoxShadow(color: AppColors.primaryLight.withOpacity(0.02), blurRadius: 30, spreadRadius: 4),
            ],
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('CORNER', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('$_current / 4', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(4, (i) {
            final active = i + 1 == _current;
            final done = i + 1 < _current;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? const Color(0xFF10B981) : (active ? AppColors.primaryLight : Colors.white12),
                border: Border.all(color: active ? Colors.white : Colors.white10),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildActionControls() {
    return Column(
      children: [
        if (_captured.isNotEmpty) ...[
          TextButton.icon(
            icon: const Icon(Icons.undo_rounded, color: Colors.white60, size: 14),
            label: const Text('UNDO LAST CORNER', style: TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.bold)),
            onPressed: () {
              setState(() {
                _captured.removeLast();
                _current = _captured.length + 1;
              });
            },
          ),
          const SizedBox(height: 16),
        ],
        ElevatedButton.icon(
          onPressed: _fetching ? null : _captureCurrentCorner,
          icon: _fetching 
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
              : const Icon(Icons.gps_fixed_rounded, color: Colors.black),
          label: Text(_fetching ? 'LOCKING GPS...' : 'CAPTURE CORNER $_current', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryLight,
            minimumSize: const Size(double.infinity, 54),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ],
    );
  }
}
