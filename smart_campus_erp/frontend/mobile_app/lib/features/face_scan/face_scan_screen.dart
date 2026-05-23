/// Production-grade face verification screen.
///
/// Features:
/// - Dynamic face guide overlay (red/yellow/green)
/// - Real-time alignment guidance
/// - Multi-challenge liveness verification
/// - Animated progress indicators
/// - Premium dark UI with glassmorphism elements
/// - Auto-capture on liveness pass
/// - Security checks before submission
library;

import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../core/constants/app_colors.dart';
import '../../core/network/api_client.dart';
import '../../core/services/device_service.dart';
import '../../core/services/security_service.dart';
import '../../core/services/location_service.dart';
import '../../core/providers/auth_provider.dart';
import '../student/providers/student_providers.dart';
import '../reports/report_providers.dart';

import 'face_scan_state.dart';
import 'face_scan_notifier.dart';
import 'face_scan_params.dart';
import 'widgets/face_overlay_painter.dart';

class FaceScanScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> session;
  final double               lat;
  final double               lng;
  final double               altitude;

  const FaceScanScreen({
    super.key,
    required this.session,
    required this.lat,
    required this.lng,
    required this.altitude,
  });

  @override
  ConsumerState<FaceScanScreen> createState() => _FaceScanScreenState();
}

class _FaceScanScreenState extends ConsumerState<FaceScanScreen>
    with SingleTickerProviderStateMixin {
  // Sensors
  double            _compassHeading  = 0.0;
  double            _maxAcceleration = 0.0;
  StreamSubscription? _compassSub;
  StreamSubscription? _accelSub;

  // Pulse animation for aligned state
  late AnimationController _pulseController;
  late Animation<double>   _pulseAnimation;

  // Permission state
  bool   _permissionChecked = false;
  String? _permissionError;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Guard against empty session
    if (widget.session.isEmpty) {
      _permissionError = 'Session data not found.';
      _permissionChecked = true;
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _compassSub?.cancel();
    _accelSub?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    // 1. Request camera permission
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) {
        setState(() {
          _permissionError = 'Camera permission denied. Please allow camera access in settings.';
          _permissionChecked = true;
        });
      }
      return;
    }

    if (mounted) {
      setState(() => _permissionChecked = true);
    }

    // 2. Initialize camera via notifier
    final notifier = ref.read(faceScanNotifierProvider.notifier);
    await notifier.initializeCamera();

    // 3. Start sensors
    _compassSub = FlutterCompass.events?.listen((event) {
      _compassHeading = event.heading ?? 0.0;
    });
    _accelSub = accelerometerEventStream().listen((event) {
      final accel = event.x * event.x + event.y * event.y + event.z * event.z;
      if (accel > _maxAcceleration) _maxAcceleration = accel;
    });
  }

  Future<void> _submitAttendance() async {
    final scanState = ref.read(faceScanNotifierProvider);
    if (scanState.capturedImageBytes == null) return;

    final notifier = ref.read(faceScanNotifierProvider.notifier);

    // 1. Security checks
    final securityError = await SecurityService.checkDeviceSecurity();
    if (securityError != null && mounted) {
      _showSecurityAlert(securityError);
      return;
    }

    // 2. Mock GPS check
    final isMocked = await LocationService().isMockLocationActive();
    if (isMocked) {
      await _handleMockLocation();
      return;
    }

    // 3. Submit
    final api   = ref.read(apiClientProvider);
    final devId = await DeviceService.getDeviceId();

    await notifier.submitAttendance(
      params: FaceScanParams(
        sessionId: widget.session['id']?.toString() ?? '',
        lat:       widget.lat,
        lng:       widget.lng,
        altitude:  widget.altitude,
        deviceId:  devId,
      ),
      api: api,
    );

    // Check result
    final resultState = ref.read(faceScanNotifierProvider);
    if (resultState.phase == FaceScanPhase.success && mounted) {
      ref.invalidate(studentActiveSessionsProvider);
      ref.invalidate(studentMyAttendanceProvider);
      ref.invalidate(studentAttendanceSummaryProvider);
      ref.invalidate(reportDashboardSummaryProvider);
      ref.invalidate(attendanceTrendsProvider);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Attendance marked successfully!'),
          backgroundColor: AppColors.success,
        ),
      );
      context.go('/student/dashboard');
    }
  }

  void _showSecurityAlert(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Security Alert'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleMockLocation() async {
    String studentId = '';
    final authState = ref.read(authProvider);
    if (authState is AuthSuccess) {
      studentId = authState.user.id;
    }

    try {
      final api   = ref.read(apiClientProvider);
      final devId = await DeviceService.getDeviceId();
      await api.post('/api/attendance/security-alert/', data: {
        'type':          'mock_location_detected',
        'student_id':    studentId,
        'attempted_lat': widget.lat,
        'attempted_lng': widget.lng,
        'timestamp':     DateTime.now().toIso8601String(),
        'device_id':     devId,
      });
    } catch (_) {}

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Security Alert'),
          content: const Text(
            'Mock location detected. Real GPS is required for attendance. '
            'Disable any fake GPS apps and try again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scanState = ref.watch(faceScanNotifierProvider);
    final notifier  = ref.read(faceScanNotifierProvider.notifier);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            // ── Camera Preview ────────────────────────────────────
            _buildCameraLayer(scanState, notifier),

            // ── Face Guide Overlay ────────────────────────────────
            if (_shouldShowOverlay(scanState))
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, _) => CustomPaint(
                  size: Size.infinite,
                  painter: FaceOverlayPainter(
                    alignmentStatus:  scanState.alignment.status,
                    overlayColor:     scanState.alignment.guidance.overlayColor,
                    pulseValue:       _pulseAnimation.value,
                    progressFraction: scanState.livenessProgress.progressFraction,
                  ),
                ),
              ),

            // ── Top Bar ───────────────────────────────────────────
            _buildTopBar(scanState),

            // ── Guidance Text ─────────────────────────────────────
            if (_shouldShowOverlay(scanState))
              _buildGuidancePanel(scanState),

            // ── Bottom Controls ───────────────────────────────────
            _buildBottomControls(scanState, notifier),

            // ── Submitting Overlay ────────────────────────────────
            if (scanState.phase == FaceScanPhase.submitting)
              _buildSubmittingOverlay(),

            // ── Success Overlay ───────────────────────────────────
            if (scanState.phase == FaceScanPhase.success)
              _buildSuccessOverlay(scanState),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraLayer(FaceScanState scanState, FaceScanNotifier notifier) {
    // Permission error
    if (_permissionError != null) {
      return _buildErrorView(_permissionError!);
    }

    // Initializing
    if (scanState.phase == FaceScanPhase.initializing || !_permissionChecked) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Starting camera...',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      );
    }

    // Error
    if (scanState.phase == FaceScanPhase.error && scanState.capturedImageBytes == null) {
      return _buildErrorView(scanState.errorMessage ?? 'An error occurred.');
    }

    // Captured photo preview
    if (scanState.capturedImageBytes != null) {
      return SizedBox.expand(
        child: Image.memory(
          scanState.capturedImageBytes as Uint8List,
          fit: BoxFit.cover,
        ),
      );
    }

    // Live camera preview
    final controller = notifier.cameraController;
    if (controller != null && controller.value.isInitialized) {
      return SizedBox.expand(child: CameraPreview(controller));
    }

    return const SizedBox.shrink();
  }

  Widget _buildErrorView(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Color(0xFFEF4444),
              size: 56,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(color: Colors.white70, fontSize: 15),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white38),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back_rounded, size: 20),
              label: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(FaceScanState scanState) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          8, MediaQuery.of(context).padding.top + 4, 8, 12,
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 22),
              onPressed: () => context.pop(),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Face Verification',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    _getSubtitle(scanState),
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
            ),
            // Liveness progress indicator
            if (scanState.phase == FaceScanPhase.liveness ||
                scanState.phase == FaceScanPhase.capturing)
              _buildProgressDots(scanState),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressDots(FaceScanState scanState) {
    final progress = scanState.livenessProgress;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(progress.totalCount, (i) {
        final isCompleted = i < progress.completedCount;
        final isCurrent   = i == progress.currentIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width:  isCurrent ? 18 : 12,
          height: 12,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: isCompleted
                ? const Color(0xFF22C55E)
                : isCurrent
                    ? const Color(0xFF3B82F6)
                    : Colors.white24,
            border: Border.all(
              color: isCompleted || isCurrent
                  ? Colors.white.withOpacity(0.3)
                  : Colors.transparent,
              width: 1,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildGuidancePanel(FaceScanState scanState) {
    final guidance = scanState.alignment.guidance;
    final isLiveness = scanState.phase == FaceScanPhase.liveness;
    final challenge = scanState.livenessProgress.currentChallenge;

    return Positioned(
      bottom: 140,
      left: 24,
      right: 24,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: Container(
          key: ValueKey(isLiveness
              ? 'liveness_${challenge?.type}'
              : 'align_${scanState.alignment.status}'),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.65),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isLiveness
                  ? const Color(0xFF3B82F6).withOpacity(0.4)
                  : guidance.overlayColor.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isLiveness
                      ? const Color(0xFF3B82F6).withOpacity(0.2)
                      : guidance.overlayColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: isLiveness && challenge != null
                      ? Text(
                          challenge.icon,
                          style: const TextStyle(fontSize: 22),
                        )
                      : Icon(
                          guidance.icon,
                          color: guidance.overlayColor,
                          size: 22,
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isLiveness ? 'Liveness Check' : 'Face Alignment',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isLiveness
                          ? challenge?.instruction ?? 'Processing...'
                          : guidance.instruction,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControls(FaceScanState scanState, FaceScanNotifier notifier) {
    // Show confirm/retake when photo is captured
    if (scanState.capturedImageBytes != null &&
        scanState.phase != FaceScanPhase.submitting &&
        scanState.phase != FaceScanPhase.success) {
      return Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: Container(
          padding: EdgeInsets.fromLTRB(
            24, 20, 24,
            MediaQuery.of(context).padding.bottom + 20,
          ),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
          child: Row(
            children: [
              // Retake button
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38),
                    minimumSize: const Size(0, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => notifier.resetForRetake(),
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  label: const Text('Retake'),
                ),
              ),
              const SizedBox(width: 16),
              // Submit button
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF22C55E),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  onPressed: _submitAttendance,
                  icon: const Icon(Icons.check_circle_rounded, size: 22),
                  label: const Text(
                    'Submit & Mark',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // During live camera — show quality score
    if (scanState.phase == FaceScanPhase.aligning ||
        scanState.phase == FaceScanPhase.liveness) {
      return Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: Container(
          padding: EdgeInsets.fromLTRB(
            24, 20, 24,
            MediaQuery.of(context).padding.bottom + 16,
          ),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Quality bar
              if (scanState.faceDetected) ...[
                Row(
                  children: [
                    Text(
                      'Quality',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: scanState.alignment.qualityScore,
                          backgroundColor: Colors.white12,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _qualityColor(scanState.alignment.qualityScore),
                          ),
                          minHeight: 4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(scanState.alignment.qualityScore * 100).toInt()}%',
                      style: TextStyle(
                        color: _qualityColor(scanState.alignment.qualityScore),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              Text(
                scanState.phase == FaceScanPhase.liveness
                    ? 'Complete all challenges to verify'
                    : 'Position your face in the oval',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildSubmittingOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.7),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 48),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withOpacity(0.1),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  color: Color(0xFF3B82F6),
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Verifying Identity',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Marking attendance...',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessOverlay(FaceScanState scanState) {
    return Container(
      color: Colors.black.withOpacity(0.85),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                color: Color(0xFF22C55E),
                size: 48,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Attendance Marked!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Verified at ${scanState.successTime ?? 'now'}',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────

  bool _shouldShowOverlay(FaceScanState scanState) {
    return scanState.capturedImageBytes == null &&
        (scanState.phase == FaceScanPhase.aligning ||
         scanState.phase == FaceScanPhase.liveness);
  }

  String _getSubtitle(FaceScanState scanState) {
    switch (scanState.phase) {
      case FaceScanPhase.initializing:
        return 'Initializing...';
      case FaceScanPhase.aligning:
        return 'Step 1: Position your face';
      case FaceScanPhase.liveness:
        final p = scanState.livenessProgress;
        return 'Step 2: Challenge ${p.completedCount + 1}/${p.totalCount}';
      case FaceScanPhase.capturing:
        return 'Capturing...';
      case FaceScanPhase.submitting:
        return 'Verifying...';
      case FaceScanPhase.success:
        return 'Done!';
      case FaceScanPhase.error:
        return 'Error';
    }
  }

  Color _qualityColor(double quality) {
    if (quality >= 0.8) return const Color(0xFF22C55E);
    if (quality >= 0.5) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }
}