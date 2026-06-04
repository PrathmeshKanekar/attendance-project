import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/layout/app_layout.dart';
import '../../core/network/api_client.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/widgets/loading_widget.dart';
import '../../core/widgets/error_widget.dart';
import '../../core/widgets/empty_state_widget.dart';
import '../../core/widgets/stat_card.dart';
import 'providers/teacher_providers.dart';
import 'services/teacher_session_heartbeat_service.dart';

class TeacherDashboardScreen extends ConsumerWidget {
  const TeacherDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppLayout(
      title: 'Teacher Dashboard',
      fab  : FloatingActionButton.extended(
        onPressed      : () => context.push('/teacher/sessions'),
        icon           : const Icon(Icons.play_arrow_rounded),
        label          : const Text('Start Session'),
        backgroundColor: AppColors.success,
      ),
      child: _TeacherDashboardBody(),
    );
  }
}

// CRITICAL FIX: extract body to prevent AppLayout rebuild
class _TeacherDashboardBody extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState     = ref.watch(authProvider);
    final user          = authState is AuthSuccess ? authState.user : null;
    final activeAsync   = ref.watch(mySessionsProvider);
    final allocAsync    = ref.watch(teacherAllocationsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        // CRITICAL FIX: only invalidate data providers
        ref.invalidate(mySessionsProvider);
        ref.invalidate(teacherAllocationsProvider);
        
        // Wait for both to complete
        await Future.wait<dynamic>([
          ref.read(mySessionsProvider.future).catchError((_) => <String, dynamic>{}),
          ref.read(teacherAllocationsProvider.future).catchError((_) => <Map<String, dynamic>>[]),
        ]);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child  : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Greeting ──────────────────────────────────
            if (user != null) ...[
              Text(
                'Hello, ${user.firstName}! 👋',
                style: const TextStyle(
                  fontSize  : 22,
                  fontWeight: FontWeight.bold,
                  color     : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                user.collegeName ?? '',
                style: const TextStyle(
                  color  : AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 20),
            ],

            // ── Stat cards ────────────────────────────────
            LayoutBuilder(
              builder: (context, constraints) {
                final crossCount = constraints.maxWidth > 600 ? 2 : 2;
                return GridView.count(
                  crossAxisCount   : crossCount,
                  shrinkWrap       : true,
                  physics          : const NeverScrollableScrollPhysics(),
                  crossAxisSpacing : 14,
                  mainAxisSpacing  : 14,
                  childAspectRatio : constraints.maxWidth > 600 ? 2.2 : 1.8,
                  children: [
                    allocAsync.when(
                      data   : (allocs) => StatCard(
                        label      : 'My Subjects',
                        value      : '${allocs.length}',
                        icon       : Icons.menu_book_rounded,
                        accentColor: AppColors.primaryLight,
                        subtitle   : 'This semester',
                      ),
                      loading: () => const StatCard(
                        label      : 'My Subjects',
                        value      : '...',
                        icon       : Icons.menu_book_rounded,
                        accentColor: AppColors.primaryLight,
                      ),
                      error  : (_, __) => const StatCard(
                        label      : 'My Subjects',
                        value      : '-',
                        icon       : Icons.menu_book_rounded,
                        accentColor: AppColors.primaryLight,
                      ),
                    ),
                    activeAsync.when(
                      data   : (data) {
                        final count = data['active_count'] as int? ?? 0;
                        return StatCard(
                          label      : 'Live Sessions',
                          value      : '$count',
                          icon       : Icons.sensors_rounded,
                          accentColor: AppColors.success,
                          subtitle   : 'Active right now',
                        );
                      },
                      loading: () => const StatCard(
                        label      : 'Live Sessions',
                        value      : '...',
                        icon       : Icons.sensors_rounded,
                        accentColor: AppColors.success,
                      ),
                      error  : (_, __) => const StatCard(
                        label      : 'Live Sessions',
                        value      : '-',
                        icon       : Icons.sensors_rounded,
                        accentColor: AppColors.success,
                      ),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 24),

            // ── Active sessions ───────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Active Sessions',
                  style: TextStyle(
                    fontSize  : 17,
                    fontWeight: FontWeight.w700,
                    color     : AppColors.textPrimary,
                  ),
                ),
                TextButton(
                  onPressed: () => context.push('/teacher/sessions'),
                  child    : const Text('View All'),
                ),
              ],
            ),
            const SizedBox(height: 10),

            activeAsync.when(
              loading: () => const LoadingWidget(),
              error  : (e, _) => AppErrorWidget(
                message: 'Could not load sessions: ${e.toString()}',
                onRetry: () => ref.invalidate(mySessionsProvider),
              ),
              data   : (data) {
                final sessions = List<Map<String, dynamic>>.from(
                  data['sessions'] as List? ?? [],
                ).where((s) => s['status'] == 'active').toList();

                if (sessions.isEmpty) {
                  return Container(
                    padding   : const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color       : AppColors.cardBg,
                      borderRadius: BorderRadius.circular(14),
                      border      : Border.all(color: AppColors.borderColor),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.event_busy_rounded,
                          size : 40,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'No active sessions',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton(
                          onPressed: () => context.push('/teacher/sessions'),
                          style    : ElevatedButton.styleFrom(
                            backgroundColor: AppColors.success,
                          ),
                          child: const Text('Start a Session'),
                        ),
                      ],
                    ),
                  );
                }

                return Column(
                  children: sessions.map((s) => _ActiveSessionCard(
                    session: s,
                    onEnd  : () async {
                      // End session
                      final api = ref.read(apiClientProvider);
                      try {
                        await api.post(
                          '/api/attendance/sessions/${s['id']}/end/',
                        );
                        ref.invalidate(mySessionsProvider);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: AppColors.danger,
                            ),
                          );
                        }
                      }
                    },
                    onViewLogs: () => context.push(
                      '/teacher/session-logs', extra: s,
                    ),
                  )).toList(),
                );
              },
            ),

            const SizedBox(height: 24),

            // ── My subjects ───────────────────────────────
            const Text(
              'My Subjects',
              style: TextStyle(
                fontSize  : 17,
                fontWeight: FontWeight.w700,
                color     : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),

            allocAsync.when(
              loading: () => const LoadingWidget(),
              error  : (e, _) => AppErrorWidget(
                message: 'Could not load subjects',
                onRetry: () => ref.invalidate(teacherAllocationsProvider),
              ),
              data   : (allocs) => allocs.isEmpty
                  ? const EmptyStateWidget(
                      message : 'No subjects allocated',
                      icon    : Icons.menu_book_outlined,
                      subtitle: 'Contact admin to assign subjects',
                    )
                  : ListView.separated(
                      shrinkWrap      : true,
                      physics         : const NeverScrollableScrollPhysics(),
                      itemCount       : allocs.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 10),
                      itemBuilder     : (context, i) =>
                          _SubjectTile(
                            allocation: allocs[i],
                            onStart   : () =>
                                context.push('/teacher/sessions'),
                          ),
                    ),
            ),

            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

// ── Active session card ────────────────────────────────────
class _ActiveSessionCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> session;
  final VoidCallback         onEnd;
  final VoidCallback         onViewLogs;

  const _ActiveSessionCard({
    super.key,
    required this.session,
    required this.onEnd,
    required this.onViewLogs,
  });

  @override
  ConsumerState<_ActiveSessionCard> createState() => _ActiveSessionCardState();
}

class _ActiveSessionCardState extends ConsumerState<_ActiveSessionCard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(teacherSessionHeartbeatProvider.notifier).startHeartbeat(
        widget.session['id'].toString(),
      );
    });
  }

  @override
  void dispose() {
    // Stop heartbeat tracker when card is destroyed
    ref.read(teacherSessionHeartbeatProvider.notifier).stopHeartbeat();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Safe parsing with defaults
    final present = (widget.session['present_count'] as num?)?.toInt() ?? 0;
    final total   = (widget.session['total_students'] as num?)?.toInt() ?? 0;
    final pct     = (widget.session['attendance_pct']  as num?)?.toDouble() ?? 
                    (total > 0 ? (present / total) * 100 : 0.0);

    final heartbeatState = ref.watch(teacherSessionHeartbeatProvider);
    final isPaused = heartbeatState.isTracking && heartbeatState.sessionStatus == 'paused';

    return Container(
      margin    : const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color       : AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border      : Border.all(
          color: isPaused ? AppColors.danger.withOpacity(0.5) : AppColors.borderColor,
          width: isPaused ? 1.5 : 1.0,
        ),
        boxShadow   : [
          BoxShadow(
            color : Colors.black.withOpacity(0.03),
            blurRadius: 10, offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Colored Status Stripe (Replaces non-uniform border)
              Container(
                width: 6,
                color: isPaused ? AppColors.danger : AppColors.success,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (!isPaused) ...[
                            _PulsingDot(),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color       : AppColors.success.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'LIVE',
                                style: TextStyle(
                                  color: AppColors.success, fontSize: 11,
                                  fontWeight: FontWeight.w800, letterSpacing: 1,
                                ),
                              ),
                            ),
                          ] else ...[
                            Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                color: AppColors.danger,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color       : AppColors.danger.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'PAUSED',
                                style: TextStyle(
                                  color: AppColors.danger, fontSize: 11,
                                  fontWeight: FontWeight.w800, letterSpacing: 1,
                                ),
                              ),
                            ),
                          ],
                          const Spacer(),
                          Text(
                            'Code: ${widget.session['session_code'] ?? 'N/A'}',
                            style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.session['subject_name']?.toString() ?? 'Untitled Subject',
                        style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold,
                          color   : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Div ${widget.session['division_name'] ?? 'A'} · '
                        'Year ${widget.session['year_of_study'] ?? 'N/A'} · '
                        'Room: ${widget.session['room_name'] ?? 'N/A'}',
                        style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13,
                        ),
                      ),

                      // Geofence Danger Warning Alert
                      if (heartbeatState.isTracking && !heartbeatState.isInside) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.danger.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'GEOFENCE WARNING: You are outside the room polygon by ${heartbeatState.distanceToBoundary.toStringAsFixed(1)}m. Attendance is PAUSED.',
                                  style: const TextStyle(
                                    color: AppColors.danger,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '$present / $total present',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                '${pct.toStringAsFixed(1)}%',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14,
                                  color: isPaused ? AppColors.danger : AppColors.success,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child       : LinearProgressIndicator(
                              value     : total > 0 ? present / total : 0,
                              backgroundColor: AppColors.bgSecondary,
                              valueColor : AlwaysStoppedAnimation(
                                isPaused ? AppColors.danger : AppColors.success,
                              ),
                              minHeight  : 8,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style    : OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primaryLight,
                                side           : const BorderSide(
                                  color: AppColors.primaryLight,
                                ),
                                minimumSize: const Size(0, 44),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: widget.onViewLogs,
                              icon : const Icon(Icons.list_alt_rounded, size: 18),
                              label: const Text('Logs'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              style    : ElevatedButton.styleFrom(
                                backgroundColor: AppColors.danger,
                                minimumSize    : const Size(0, 44),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: widget.onEnd,
                              icon : const Icon(
                                Icons.stop_circle_rounded, size: 18,
                              ),
                              label: const Text('End'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Subject tile ───────────────────────────────────────────
class _SubjectTile extends StatelessWidget {
  final Map<String, dynamic> allocation;
  final VoidCallback         onStart;
  const _SubjectTile({required this.allocation, required this.onStart});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding   : const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color       : AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border      : Border.all(color: AppColors.borderColor),
      ),
      child: Row(
        children: [
          Container(
            width : 44, height: 44,
            decoration: BoxDecoration(
              color       : AppColors.primaryLight.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.menu_book_rounded,
              color: AppColors.primaryLight, size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  allocation['subject_name']?.toString() ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14,
                    color     : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${allocation['subject_code'] ?? ''} · '
                  'Div ${allocation['division_name'] ?? ''} · '
                  'Y${allocation['division_year'] ?? allocation['year_of_study'] ?? ''}',
                  style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: onStart,
            style    : ElevatedButton.styleFrom(
              minimumSize    : const Size(80, 38),
              backgroundColor: AppColors.success,
              shape          : RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Start', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}
class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _anim = Tween(begin: 0.4, end: 1.0).animate(_ctrl);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _anim,
    child  : Container(
      width: 10, height: 10,
      decoration: const BoxDecoration(
        color: AppColors.success, shape: BoxShape.circle,
      ),
    ),
  );
}
