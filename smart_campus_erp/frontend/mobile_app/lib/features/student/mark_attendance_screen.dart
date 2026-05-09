import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/network/api_client.dart';

// ── Geo check state ────────────────────────────────────────
abstract class GeoState {}
class GeoIdle     extends GeoState {}
class GeoChecking extends GeoState {}
class GeoInside   extends GeoState {
  final Map<String, dynamic> result;
  GeoInside(this.result);
}
class GeoOutside  extends GeoState {
  final double distanceMeters;
  GeoOutside(this.distanceMeters);
}
class GeoError    extends GeoState {
  final String message;
  GeoError(this.message);
}

class MarkAttendanceScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> session;
  const MarkAttendanceScreen({super.key, required this.session});

  @override
  ConsumerState<MarkAttendanceScreen> createState() =>
      _MarkAttendanceScreenState();
}

class _MarkAttendanceScreenState
    extends ConsumerState<MarkAttendanceScreen>
    with SingleTickerProviderStateMixin {

  GeoState _geoState  = GeoIdle();
  double?  _currentLat;
  double?  _currentLng;
  double?  _currentAlt;
  bool     _isChecking = false;

  // Animation for inside check bounce
  late AnimationController _bounceCtrl;
  late Animation<double>   _bounceAnim;

  @override
  void initState() {
    super.initState();
    _bounceCtrl = AnimationController(
      vsync   : this,
      duration: const Duration(milliseconds: 600),
    );
    _bounceAnim = CurvedAnimation(
      parent: _bounceCtrl,
      curve : Curves.elasticOut,
    );
    // Auto-check location on screen open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLocation();
    });
  }

  @override
  void dispose() {
    _bounceCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkLocation() async {
    if (_isChecking) return;
    setState(() {
      _isChecking = true;
      _geoState   = GeoChecking();
    });

    try {
      // ── Permission checks ─────────────────────────
      bool enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        setState(() {
          _geoState   = GeoError('Location services are disabled.\nPlease enable GPS in device settings.');
          _isChecking = false;
        });
        return;
      }

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        setState(() {
          _geoState   = GeoError('Location permission denied.\nPlease allow location access in settings.');
          _isChecking = false;
        });
        return;
      }

      // ── Get GPS position ──────────────────────────
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit      : const Duration(seconds: 15),
      );

      _currentLat = pos.latitude;
      _currentLng = pos.longitude;
      _currentAlt = pos.altitude;

      // ── Ask backend if inside room ─────────────────
      final api = ref.read(apiClientProvider);
      final res = await api.post(
        '/api/attendance/check-location/',
        data: {
          'session_id': widget.session['id'],
          'lat'       : pos.latitude,
          'lng'       : pos.longitude,
          'altitude'  : pos.altitude,
        },
      );

      if (res.data['is_inside'] == true) {
        setState(() => _geoState = GeoInside(
          Map<String, dynamic>.from(res.data as Map),
        ));
        _bounceCtrl.forward(from: 0);
      } else {
        final dist = (res.data['distance_to_boundary'] as num?)
            ?.toDouble() ?? 0.0;
        setState(() => _geoState = GeoOutside(dist));
      }
    } catch (e) {
      String msg = e.toString();
      if (msg.contains('TimeoutException')) {
        msg = 'GPS signal too weak. Move to open area and try again.';
      } else if (msg.contains('NETWORK_ERROR') ||
                 msg.contains('SocketException')) {
        msg = 'No internet connection. Check your network.';
      }
      setState(() => _geoState = GeoError(msg));
    } finally {
      setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Null safety guard
    if (widget.session.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mark Attendance')),
        body  : const Center(
          child: Text('Session data not found. Go back and try again.'),
        ),
      );
    }

    return PopScope(
      // CRITICAL FIX: prevent accidental back during GPS checking
      canPop: _geoState is! GeoChecking,
      child: Scaffold(
        backgroundColor: AppColors.bgPrimary,
        appBar         : AppBar(
          title          : const Text('Mark Attendance'),
          backgroundColor: AppColors.cardBg,
          elevation      : 0,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            icon     : const Icon(Icons.arrow_back_rounded),
            onPressed: _geoState is GeoChecking
                ? null
                : () => Navigator.of(context).pop(),
          ),
        ),
        body: Column(
          children: [

            // ── Step progress bar ────────────────────
            _StepProgressBar(
              currentStep: _geoState is GeoInside ? 2 : 1,
            ),

            // ── Session info card ────────────────────
            _SessionInfoCard(session: widget.session),

            // ── Main body ────────────────────────────
            Expanded(
              child: AnimatedSwitcher(
                duration       : const Duration(milliseconds: 400),
                switchInCurve  : Curves.easeIn,
                switchOutCurve : Curves.easeOut,
                child          : _buildBody(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final state = _geoState;

    // ── Checking state ────────────────────────────────
    if (state is GeoChecking || state is GeoIdle) {
      return const _CheckingBody(key: ValueKey('checking'));
    }

    // ── Inside room ────────────────────────────────────
    if (state is GeoInside) {
      return _InsideBody(
        key         : const ValueKey('inside'),
        result      : state.result,
        bounceAnim  : _bounceAnim,
        session     : widget.session,
        lat         : _currentLat ?? 0.0,
        lng         : _currentLng ?? 0.0,
        altitude    : _currentAlt ?? 0.0,
      );
    }

    // ── Outside room ───────────────────────────────────
    if (state is GeoOutside) {
      return _OutsideBody(
        key             : const ValueKey('outside'),
        distanceMeters  : state.distanceMeters,
        onRetry         : _checkLocation,
      );
    }

    // ── Error state ────────────────────────────────────
    if (state is GeoError) {
      return _ErrorBody(
        key     : const ValueKey('error'),
        message : state.message,
        onRetry : _checkLocation,
      );
    }

    return const SizedBox.shrink();
  }
}


// ══════════════════════════════════════════════════════════
// SESSION INFO CARD
// ══════════════════════════════════════════════════════════

class _SessionInfoCard extends StatelessWidget {
  final Map<String, dynamic> session;
  const _SessionInfoCard({required this.session});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin   : const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding  : const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color       : AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border      : Border.all(color: AppColors.borderColor),
      ),
      child: Row(
        children: [
          Container(
            width : 42, height: 42,
            decoration: BoxDecoration(
              color       : AppColors.primaryLight.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.menu_book_rounded,
              color: AppColors.primaryLight,
              size : 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session['subject_name']?.toString() ?? 'Subject',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize  : 15,
                    color     : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Code: ${session['session_code'] ?? ''} · '
                  'Room: ${session['room_name'] ?? 'N/A'}',
                  style: const TextStyle(
                    color  : AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // Live badge
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 8, vertical: 4,
            ),
            decoration: BoxDecoration(
              color       : AppColors.success.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children    : [
                Container(
                  width : 6, height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                const Text(
                  'LIVE',
                  style: TextStyle(
                    color     : AppColors.success,
                    fontSize  : 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


// ══════════════════════════════════════════════════════════
// CHECKING BODY — Pulsing rings animation
// ══════════════════════════════════════════════════════════

class _CheckingBody extends StatefulWidget {
  const _CheckingBody({super.key});

  @override
  State<_CheckingBody> createState() => _CheckingBodyState();
}

class _CheckingBodyState extends State<_CheckingBody>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync   : this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _anim,
            builder  : (_, __) => Stack(
              alignment: Alignment.center,
              children : [
                _ring(100 + _anim.value * 20, 0.06),
                _ring(75  + _anim.value * 15, 0.10),
                _ring(50  + _anim.value * 10, 0.18),
                Container(
                  width : 48, height: 48,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryLight,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.gps_fixed_rounded,
                    color: Colors.white,
                    size : 26,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'Checking your location...',
            style: TextStyle(
              fontSize  : 17,
              fontWeight: FontWeight.w600,
              color     : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Please stay still while we verify\nyou are inside the classroom.',
            textAlign: TextAlign.center,
            style    : TextStyle(
              color  : AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _ring(double size, double opacity) => Container(
    width     : size, height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: AppColors.primaryLight.withOpacity(opacity),
    ),
  );
}


// ══════════════════════════════════════════════════════════
// INSIDE BODY — Green check + Mark button
// ══════════════════════════════════════════════════════════

class _InsideBody extends ConsumerWidget {
  final Map<String, dynamic> result;
  final Animation<double>    bounceAnim;
  final Map<String, dynamic> session;
  final double               lat;
  final double               lng;
  final double               altitude;

  const _InsideBody({
    super.key,
    required this.result,
    required this.bounceAnim,
    required this.session,
    required this.lat,
    required this.lng,
    required this.altitude,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roomName = result['room_name']?.toString()
        ?? session['room_name']?.toString()
        ?? 'Classroom';
    final distance = (result['distance_from_center'] as num?)
        ?.toStringAsFixed(1) ?? '0';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child  : Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [

          // Bouncing green check circle
          ScaleTransition(
            scale: bounceAnim,
            child: Container(
              width : 110, height: 110,
              decoration: const BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                color: Colors.white,
                size : 65,
              ),
            ),
          ),

          const SizedBox(height: 24),

          const Text(
            'You are inside',
            style: TextStyle(
              fontSize  : 16,
              color     : AppColors.textSecondary,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            roomName,
            textAlign: TextAlign.center,
            style    : const TextStyle(
              fontSize  : 22,
              fontWeight: FontWeight.bold,
              color     : AppColors.textPrimary,
            ),
          ),

          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 6,
            ),
            decoration: BoxDecoration(
              color       : AppColors.success.withOpacity(0.10),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${distance}m from center · Location verified ✓',
              style: const TextStyle(
                color    : AppColors.success,
                fontSize : 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

          const SizedBox(height: 40),

          // Mark attendance button — navigates to face scan
          SizedBox(
            width : double.infinity,
            child : ElevatedButton.icon(
              style    : ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                minimumSize    : const Size(double.infinity, 58),
                shape          : RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 2,
              ),
              onPressed: () {
                context.push(
                  '/student/face-scan/${session['id']}',
                );
              },
              icon : const Icon(
                Icons.face_rounded,
                size: 24,
              ),
              label: const Text(
                'Mark Attendance →',
                style: TextStyle(
                  fontSize  : 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Info text
          const Text(
            'Next: Face scan + 3 eye blinks to confirm',
            style: TextStyle(
              color  : AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}


// ══════════════════════════════════════════════════════════
// OUTSIDE BODY — Red icon + distance + retry
// ══════════════════════════════════════════════════════════

class _OutsideBody extends StatelessWidget {
  final double       distanceMeters;
  final VoidCallback onRetry;

  const _OutsideBody({
    super.key,
    required this.distanceMeters,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child  : Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [

          Container(
            width : 100, height: 100,
            decoration: BoxDecoration(
              color       : AppColors.danger.withOpacity(0.10),
              shape       : BoxShape.circle,
            ),
            child: const Icon(
              Icons.location_off_rounded,
              size : 56,
              color: AppColors.danger,
            ),
          ),

          const SizedBox(height: 24),

          Text(
            '${distanceMeters.toStringAsFixed(0)}m away',
            style: const TextStyle(
              fontSize  : 28,
              fontWeight: FontWeight.w800,
              color     : AppColors.danger,
            ),
          ),

          const SizedBox(height: 8),

          const Text(
            'You are outside the classroom boundary.',
            style: TextStyle(
              fontSize  : 16,
              fontWeight: FontWeight.w600,
              color     : AppColors.textPrimary,
            ),
          ),

          const SizedBox(height: 8),

          const Text(
            'Move closer to the classroom and try again.\n'
            'Make sure your GPS is turned on.',
            textAlign: TextAlign.center,
            style    : TextStyle(
              color  : AppColors.textSecondary,
              fontSize: 13,
            ),
          ),

          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style    : OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                side       : const BorderSide(
                  color: AppColors.primaryLight,
                  width: 2,
                ),
              ),
              onPressed: onRetry,
              icon : const Icon(Icons.refresh_rounded),
              label: const Text(
                'Check Again',
                style: TextStyle(fontSize: 15),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Disabled mark button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style    : ElevatedButton.styleFrom(
                backgroundColor: AppColors.borderColor,
                minimumSize    : const Size(double.infinity, 52),
                shape          : RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              onPressed: null,
              icon : const Icon(Icons.face_rounded),
              label: const Text('Mark Attendance'),
            ),
          ),
        ],
      ),
    );
  }
}


// ══════════════════════════════════════════════════════════
// ERROR BODY
// ══════════════════════════════════════════════════════════

class _ErrorBody extends StatelessWidget {
  final String       message;
  final VoidCallback onRetry;

  const _ErrorBody({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child  : Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [

          Container(
            width : 100, height: 100,
            decoration: BoxDecoration(
              color : AppColors.warning.withOpacity(0.10),
              shape : BoxShape.circle,
            ),
            child: const Icon(
              Icons.gps_off_rounded,
              size : 56,
              color: AppColors.warning,
            ),
          ),

          const SizedBox(height: 24),

          const Text(
            'Location Error',
            style: TextStyle(
              fontSize  : 20,
              fontWeight: FontWeight.bold,
              color     : AppColors.textPrimary,
            ),
          ),

          const SizedBox(height: 10),

          Text(
            message,
            textAlign: TextAlign.center,
            style    : const TextStyle(
              color  : AppColors.textSecondary,
              fontSize: 14,
            ),
          ),

          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style    : ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
              ),
              onPressed: onRetry,
              icon : const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
            ),
          ),
        ],
      ),
    );
  }
}


// ══════════════════════════════════════════════════════════
// STEP PROGRESS BAR
// ══════════════════════════════════════════════════════════

class _StepProgressBar extends StatelessWidget {
  final int currentStep;
  const _StepProgressBar({required this.currentStep});

  @override
  Widget build(BuildContext context) {
    final steps = ['Location', 'Face', 'Blinks', 'Done'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color  : AppColors.cardBg,
      child  : Row(
        children: List.generate(steps.length * 2 - 1, (i) {
          if (i.isOdd) {
            final stepIndex = (i ~/ 2) + 1;
            return Expanded(
              child: Container(
                height: 2,
                color : stepIndex < currentStep
                    ? AppColors.success
                    : AppColors.borderColor,
              ),
            );
          }
          final stepIndex = i ~/ 2 + 1;
          final isDone    = stepIndex < currentStep;
          final isActive  = stepIndex == currentStep;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children    : [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width   : 32, height: 32,
                decoration: BoxDecoration(
                  color : isDone
                      ? AppColors.success
                      : isActive
                          ? AppColors.primaryLight
                          : AppColors.bgSecondary,
                  shape : BoxShape.circle,
                  border: Border.all(
                    color: isDone
                        ? AppColors.success
                        : isActive
                            ? AppColors.primaryLight
                            : AppColors.borderColor,
                    width: 2,
                  ),
                ),
                child: Center(
                  child: isDone
                      ? const Icon(Icons.check, color: Colors.white, size: 16)
                      : Text(
                          '$stepIndex',
                          style: TextStyle(
                            color     : isActive
                                ? Colors.white
                                : AppColors.textSecondary,
                            fontSize  : 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                steps[stepIndex - 1],
                style: TextStyle(
                  fontSize  : 10,
                  color     : isActive || isDone
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  fontWeight: isActive
                      ? FontWeight.w700
                      : FontWeight.normal,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}
