import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:math' as math;

import '../../../../core/constants/app_colors.dart';
import '../../../../core/layout/app_layout.dart';
import '../providers/virtual_room_providers.dart';
import '../painters/room_preview_painter.dart';

class RoomPreviewScreen extends ConsumerStatefulWidget {
  final String roomId;
  const RoomPreviewScreen({super.key, required this.roomId});

  @override
  ConsumerState<RoomPreviewScreen> createState() => _RoomPreviewScreenState();
}

class _RoomPreviewScreenState extends ConsumerState<RoomPreviewScreen> {
  Map<String, double>? _simulatedUser; // simulated offset X/Y metres

  @override
  Widget build(BuildContext context) {
    final previewAsync = ref.watch(roomPreviewProvider(widget.roomId));

    return AppLayout(
      title: 'Spatial Vector Frame',
      child: Container(
        color: AppColors.bgPrimary,
        child: previewAsync.when(
          data: (data) {
            final cornersRaw = data['normalized_coordinates'] as List<dynamic>? ?? [];
            final length = (data['length'] as num? ?? 10.0).toDouble();
            final width = (data['width'] as num? ?? 10.0).toDouble();
            final area = (data['area'] as num? ?? 100.0).toDouble();
            final heading = (data['magnetic_heading'] as num? ?? 0.0).toStringAsFixed(1);

            final corners = cornersRaw.map((e) {
              final m = Map<String, dynamic>.from(e as Map);
              return {
                'x': (m['x'] as num? ?? 0.0).toDouble(),
                'y': (m['y'] as num? ?? 0.0).toDouble(),
                'z': (m['z'] as num? ?? 0.0).toDouble(),
              };
            }).toList();

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildIntroHeader(),
                  const SizedBox(height: 16),
                  
                  // Interactive preview canvas
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final double sizeW = constraints.maxWidth;
                        final double sizeH = constraints.maxHeight;

                        return GestureDetector(
                          onTapUp: (details) {
                            final double cx = details.localPosition.dx;
                            final double cy = details.localPosition.dy;

                            // Re-calculate scale parameters mirroring RoomPreviewPainter
                            final padding = 50.0;
                            final drawW = sizeW - (padding * 2);
                            final drawH = sizeH - (padding * 2);

                            final xVals = corners.map((c) => c['x'] ?? 0.0).toList();
                            final yVals = corners.map((c) => c['y'] ?? 0.0).toList();

                            final minX = xVals.isEmpty ? 0.0 : xVals.reduce(math.min);
                            final maxX = xVals.isEmpty ? 10.0 : xVals.reduce(math.max);
                            final minY = yVals.isEmpty ? 0.0 : yVals.reduce(math.min);
                            final maxY = yVals.isEmpty ? 10.0 : yVals.reduce(math.max);

                            final rangeX = (maxX - minX).abs() < 0.1 ? 1.0 : (maxX - minX);
                            final rangeY = (maxY - minY).abs() < 0.1 ? 1.0 : (maxY - minY);

                            final scale = math.min(drawW / rangeX, drawH / rangeY);

                            final rx = minX + (cx - padding - (drawW - (maxX - minX) * scale) / 2) / scale;
                            final ry = minY + (sizeH - padding - cy - (drawH - (maxY - minY) * scale) / 2) / scale;

                            setState(() {
                              _simulatedUser = {
                                'x': rx.clamp(minX, maxX),
                                'y': ry.clamp(minY, maxY),
                              };
                            });
                          },
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: AppColors.borderColor),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, spreadRadius: 2),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: CustomPaint(
                                painter: RoomPreviewPainter(
                                  corners: corners,
                                  userOffset: _simulatedUser,
                                  headingAngle: heading,
                                  length: length,
                                  width: width,
                                  area: area,
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                    ),
                  ),

                  const SizedBox(height: 16),
                  _buildControlPanel(length, width, area, heading),
                ],
              ),
            );
          },
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
          error: (err, stack) => _buildErrorState(err.toString()),
        ),
      ),
    );
  }

  Widget _buildIntroHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 16),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Tap anywhere inside the frame to simulate student location and verify polygon containment.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel(double len, double wid, double area, String head) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.borderColor),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _metricItem('LENGTH', '${len.toStringAsFixed(1)} m'),
              _metricItem('WIDTH', '${wid.toStringAsFixed(1)} m'),
              _metricItem('AREA', '${area.toStringAsFixed(1)} m²'),
              _metricItem('HEADING', '$head°'),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() => _simulatedUser = null);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.borderColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Reset Simulation'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => context.pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Back to Details', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricItem(String label, String val) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        const SizedBox(height: 4),
        Text(val, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w900)),
      ],
    );
  }

  Widget _buildErrorState(String err) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.spatial_audio_off_rounded, size: 52, color: AppColors.danger),
            const SizedBox(height: 16),
            const Text('Spatial Engine Offline', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(err, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => ref.refresh(roomPreviewProvider(widget.roomId)),
              child: const Text('RETRY FRAME SYNC'),
            ),
          ],
        ),
      ),
    );
  }
}
