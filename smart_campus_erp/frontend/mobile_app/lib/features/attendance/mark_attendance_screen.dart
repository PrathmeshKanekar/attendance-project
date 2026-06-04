import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_campus_app/core/layout/app_layout.dart';
import 'package:smart_campus_app/core/services/device_service.dart';
import 'package:smart_campus_app/features/face_scan/face_scan_params.dart';
import 'providers/attendance_state_provider.dart';

class SessionModel {
  final String id;
  final String subjectName;
  const SessionModel({required this.id, required this.subjectName});
}

class MarkAttendanceScreen extends ConsumerStatefulWidget {
  final SessionModel session;
  const MarkAttendanceScreen({super.key, required this.session});

  @override
  ConsumerState<MarkAttendanceScreen> createState() => _MarkAttendanceScreenState();
}

class _MarkAttendanceScreenState extends ConsumerState<MarkAttendanceScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    // Start real-time spatial geofence verification
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(attendanceStateProvider.notifier).startRealTimeVerification(widget.session.id);
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(attendanceStateProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final Color statusColor = _getStatusColor(state.status);
    final IconData statusIcon = _getStatusIcon(state.status);
    final bool canSubmit = state.status == AttendanceValidationStatus.inside;

    return AppLayout(
      title: widget.session.subjectName,
      child: SafeArea(
        child: Column(
          children: [
            // STEP PROGRESS TRACKER HUD
            Container(
              color: const Color(0xFF1E293B),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  _buildProgressStep(1, 'Boundary Check', statusColor, isActive: true),
                  _buildProgressLine(statusColor),
                  _buildProgressStep(2, 'Face Identity', Colors.grey.shade600, isActive: false),
                  _buildProgressLine(Colors.white12),
                  _buildProgressStep(3, 'Mark Present', Colors.grey.shade600, isActive: false),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    // LIVE INSIDE/OUTSIDE SPATIAL BANNER
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: statusColor.withOpacity(0.2), width: 1.5),
                      ),
                      child: Row(
                        children: [
                          Icon(statusIcon, color: statusColor, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _getStatusHeading(state.status),
                                  style: TextStyle(
                                    color: statusColor,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  state.message,
                                  style: TextStyle(
                                    color: isDark ? Colors.white70 : Colors.black87,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // RADAR GEOMAP blue canvas
                    if (state.status != AttendanceValidationStatus.idle &&
                        state.status != AttendanceValidationStatus.error) ...[
                      Container(
                        height: 260,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white.withOpacity(0.06)),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Stack(
                            children: [
                              CustomPaint(
                                size: Size.infinite,
                                painter: RadarPolygonPainter(
                                  polygon: state.roomPolygon,
                                  studentLat: state.currentLat,
                                  studentLng: state.currentLng,
                                  primaryColor: theme.primaryColor,
                                  accentColor: statusColor,
                                ),
                              ),
                              // Radar sweep dial overlay animation
                              Positioned.fill(
                                child: RotationTransition(
                                  turns: _pulseController,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: SweepGradient(
                                        center: Alignment.center,
                                        colors: [
                                          theme.primaryColor.withOpacity(0.0),
                                          theme.primaryColor.withOpacity(0.08),
                                          theme.primaryColor.withOpacity(0.0),
                                        ],
                                        stops: const [0.0, 0.5, 1.0],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 12,
                                left: 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.6),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    state.roomName,
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // HUD TELEMETRIES PANEL
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.06)),
                      ),
                      child: Column(
                        children: [
                          _buildHudField('GPS PRECISION', '±${state.gpsAccuracy.toStringAsFixed(1)} meters'),
                          _buildHudField('COMPASS HEADING', '${state.compassDegrees.toStringAsFixed(0)}° ${state.directionLabel}'),
                          _buildHudField('DISTANCE TO CLASSROOM', '${state.distanceToBoundary.toStringAsFixed(1)} m'),
                          _buildHudField('SENSORS INTEGRITY', '${state.securityConfidence.toStringAsFixed(0)}% (Secure)'),
                          const Divider(color: Colors.white10, height: 20),
                          Row(
                            children: [
                              const Icon(Icons.security_rounded, size: 16, color: Colors.green),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'SmartCampus Geofencing Engine active.',
                                  style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                                ),
                              ),
                            ],
                          )
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // CAPTURE SUBMIT ACTION BUTTON
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: canSubmit ? Colors.green.shade600 : Colors.grey.shade800,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: canSubmit ? _navigateToFaceScan : null,
                        icon: const Icon(Icons.face_rounded),
                        label: Text(
                          canSubmit ? 'Verify Face & Liveness →' : 'Geofence Verification Required',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToFaceScan() async {
    final state = ref.read(attendanceStateProvider);
    final deviceId = await DeviceService.getDeviceId();
    if (mounted) {
      context.push('/face-scan', extra: FaceScanParams(
        sessionId: widget.session.id,
        lat: state.currentLat,
        lng: state.currentLng,
        altitude: state.currentAlt,
        deviceId: deviceId,
      ));
    }
  }

  Color _getStatusColor(AttendanceValidationStatus s) {
    switch (s) {
      case AttendanceValidationStatus.inside:
        return Colors.green.shade400;
      case AttendanceValidationStatus.outside:
        return Colors.amber.shade500;
      case AttendanceValidationStatus.spoofed:
        return Colors.red.shade400;
      case AttendanceValidationStatus.error:
        return Colors.orange.shade500;
      default:
        return Colors.blue.shade400;
    }
  }

  IconData _getStatusIcon(AttendanceValidationStatus s) {
    switch (s) {
      case AttendanceValidationStatus.inside:
        return Icons.check_circle_rounded;
      case AttendanceValidationStatus.outside:
        return Icons.location_off_rounded;
      case AttendanceValidationStatus.spoofed:
        return Icons.security_rounded;
      case AttendanceValidationStatus.error:
        return Icons.warning_rounded;
      default:
        return Icons.gps_fixed_rounded;
    }
  }

  String _getStatusHeading(AttendanceValidationStatus s) {
    switch (s) {
      case AttendanceValidationStatus.inside:
        return 'INSIDE CLASSROOM Area';
      case AttendanceValidationStatus.outside:
        return 'OUTSIDE CLASSROOM Area';
      case AttendanceValidationStatus.spoofed:
        return 'SECURITY LOCKOUT';
      case AttendanceValidationStatus.error:
        return 'ERROR IDENTIFIED';
      default:
        return 'ACQUIRING POSITIONS';
    }
  }

  Widget _buildProgressStep(int stepNum, String label, Color color, {required bool isActive}) {
    return Row(
      children: [
        CircleAvatar(
          radius: 11,
          backgroundColor: color.withOpacity(isActive ? 1.0 : 0.4),
          child: Text('$stepNum', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(color: isActive ? Colors.white : Colors.white24, fontSize: 11, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildProgressLine(Color color) {
    return Expanded(
      child: Container(
        height: 1.5,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        color: color,
      ),
    );
  }

  Widget _buildHudField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.white54, fontWeight: FontWeight.bold)),
          Text(value, style: const TextStyle(fontSize: 11, color: Colors.white, fontFamily: 'monospace', fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RADAR PAINTER
// ─────────────────────────────────────────────────────────────────────────────
class RadarPolygonPainter extends CustomPainter {
  final List<Map<String, double>> polygon;
  final double studentLat;
  final double studentLng;
  final Color primaryColor;
  final Color accentColor;

  RadarPolygonPainter({
    required this.polygon,
    required this.studentLat,
    required this.studentLng,
    required this.primaryColor,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw Radar grid backgrounds
    final centerOffset = Offset(size.width / 2, size.height / 2);
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.04)
      ..strokeWidth = 1.0;
    
    for (double i = 0.0; i < size.width; i += 30) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), gridPaint);
    }
    for (double i = 0.0; i < size.height; i += 30) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), gridPaint);
    }
    
    // Draw concentric circles
    final circlePaint = Paint()
      ..color = Colors.white.withOpacity(0.03)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (double r = 40; r < size.width; r += 40) {
      canvas.drawCircle(centerOffset, r, circlePaint);
    }

    if (polygon.isEmpty) return;

    // 2. Identify projection scale parameters
    double minLat = double.infinity, maxLat = -double.infinity;
    double minLng = double.infinity, maxLng = -double.infinity;

    List<double> lats = polygon.map((e) => e['lat']!).toList();
    List<double> lngs = polygon.map((e) => e['lng']!).toList();
    
    // Include student to prevent layout out-of-bounds clipping
    lats.add(studentLat);
    lngs.add(studentLng);

    for (final lat in lats) {
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
    }
    for (final lng in lngs) {
      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
    }

    double latSpan = maxLat - minLat;
    double lngSpan = maxLng - minLng;
    if (latSpan == 0.0) latSpan = 0.0001;
    if (lngSpan == 0.0) lngSpan = 0.0001;

    const pad = 36.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;

    // 3. Project coordinates
    List<Offset> screenPoints = [];
    for (final p in polygon) {
      double x = pad + ((p['lng']! - minLng) / lngSpan) * w;
      double y = pad + (1.0 - ((p['lat']! - minLat) / latSpan)) * h;
      screenPoints.add(Offset(x, y));
    }

    double studentX = pad + ((studentLng - minLng) / lngSpan) * w;
    double studentY = pad + (1.0 - ((studentLat - minLat) / latSpan)) * h;
    final studentPt = Offset(studentX, studentY);

    // 4. Draw polygon classroom fills
    final fillPaint = Paint()
      ..color = primaryColor.withOpacity(0.12)
      ..style = PaintingStyle.fill;
    
    final borderPaint = Paint()
      ..color = primaryColor.withOpacity(0.8)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    path.moveTo(screenPoints[0].dx, screenPoints[0].dy);
    for (int i = 1; i < screenPoints.length; i++) {
      path.lineTo(screenPoints[i].dx, screenPoints[i].dy);
    }
    path.close();

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, borderPaint);

    // Corners indicators
    final cornerPaint = Paint()..color = primaryColor;
    for (final pt in screenPoints) {
      canvas.drawCircle(pt, 4.0, cornerPaint);
    }

    // 5. Draw Student Dot & Pulse
    final studentPulse = Paint()
      ..color = accentColor.withOpacity(0.25)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(studentPt, 15.0, studentPulse);

    final studentPaint = Paint()..color = accentColor;
    canvas.drawCircle(studentPt, 5.0, studentPaint);
  }

  @override
  bool shouldRepaint(covariant RadarPolygonPainter oldDelegate) => true;
}
