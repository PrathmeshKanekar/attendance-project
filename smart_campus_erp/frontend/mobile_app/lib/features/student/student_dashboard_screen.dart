import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/layout/app_layout.dart';
import '../../core/network/api_client.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/widgets/empty_state_widget.dart';
import '../../core/widgets/error_widget.dart';
import '../../core/widgets/loading_widget.dart';
import '../../core/widgets/stat_card.dart';
import '../reports/report_providers.dart';


// CRITICAL FIX: Make summary provider auth-aware and handle both List/Map responses
final studentAttendanceSummaryProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final listAsync = ref.watch(studentMyAttendanceProvider);
  
  return listAsync.when(
    data: (list) {
      int total    = list.length;
      int atRisk   = list.where((s) => (s['percentage'] as num? ?? 0) < 75).length;
      double avg   = total == 0
          ? 0
          : list.fold(0.0, (sum, s) => sum + (s['percentage'] as num? ?? 0)) / total;

      return {
        'total_subjects': total,
        'at_risk'        : atRisk,
        'average_pct'    : avg.toStringAsFixed(1),
        'subjects'       : list,
      };
    },
    loading: () => {'total_subjects': 0, 'at_risk': 0, 'average_pct': '0', 'subjects': []},
    error: (e, _) => throw e,
  );
});

// CRITICAL FIX: Make active sessions provider auth-aware
final studentActiveSessionsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final authState = ref.watch(authProvider);
  if (authState is! AuthSuccess) return [];

  final api = ref.read(apiClientProvider);
  try {
    final res = await api.get('/api/attendance/sessions/active/');
    if (res.data is List) {
      return List<Map<String, dynamic>>.from(
        (res.data as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
    }
    return [];
  } catch (e) {
    rethrow;
  }
});


class StudentDashboardScreen extends ConsumerWidget {
  const StudentDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // CRITICAL FIX: use select() — only rebuild when user changes
    final user = ref.watch(
      authProvider.select((s) => s is AuthSuccess ? s.user : null),
    );

    if (user == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // BUG 4 FIX: AppLayout receives only the _Body widget as child
    // RefreshIndicator lives inside _Body only — sidebar stays
    return AppLayout(
      title: 'Student Dashboard',
      child: _DashboardBody(user: user),
    );
  }
}

// BUG 4 FIX: Extract scrollable body into private ConsumerWidget
class _DashboardBody extends ConsumerWidget {
  final dynamic user;
  const _DashboardBody({required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync  = ref.watch(studentAttendanceSummaryProvider);
    final sessionsAsync = ref.watch(studentActiveSessionsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        // BUG 4 FIX: only invalidate DATA providers not authProvider
        ref.invalidate(studentAttendanceSummaryProvider);
        ref.invalidate(studentActiveSessionsProvider);
        await ref.read(studentAttendanceSummaryProvider.future);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Greeting
            Text(
              'Welcome, ${user.firstName}! 👋',
              style: const TextStyle(
                fontSize  : 22,
                fontWeight: FontWeight.bold,
                color     : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${user.collegeName ?? "Campus ERP"} · PRN: ${user.prn ?? "N/A"}',
              style: const TextStyle(
                color  : AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 24),

            // Stat cards
            summaryAsync.when(
              loading: () => const LoadingWidget(message: 'Loading stats...'),
              error  : (e, _) => AppErrorWidget(
                message: e.toString(),
                onRetry: () => ref.invalidate(studentAttendanceSummaryProvider),
              ),
              data   : (summary) => GridView.count(
                crossAxisCount  : MediaQuery.of(context).size.width > 600 ? 4 : 2,
                shrinkWrap      : true,
                physics         : const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 16,
                mainAxisSpacing : 16,
                childAspectRatio: 1.2,
                children: [
                  StatCard(
                    label      : 'Avg Attendance',
                    value      : '${summary['average_pct']}%',
                    icon       : Icons.bar_chart_rounded,
                    accentColor: _pctColor(
                      double.tryParse(summary['average_pct'].toString()) ?? 0,
                    ),
                    subtitle   : 'Across all subjects',
                  ),
                  StatCard(
                    label      : 'Subjects',
                    value      : '${summary['total_subjects']}',
                    icon       : Icons.menu_book_rounded,
                    accentColor: AppColors.primaryLight,
                    subtitle   : 'Enrolled this semester',
                  ),
                  StatCard(
                    label      : 'At Risk',
                    value      : '${summary['at_risk']}',
                    icon       : Icons.warning_amber_rounded,
                    accentColor: AppColors.danger,
                    subtitle   : 'Below 75%',
                  ),
                  StatCard(
                    label      : 'Active Now',
                    value      : sessionsAsync.maybeWhen(
                      data : (s) => '${s.length}',
                      orElse: () => '-',
                    ),
                    icon       : Icons.play_circle_rounded,
                    accentColor: AppColors.success,
                    subtitle   : 'Live sessions',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Active sessions
            const Text(
              'Active Sessions',
              style: TextStyle(
                fontSize  : 17,
                fontWeight: FontWeight.w700,
                color     : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),

            sessionsAsync.when(
              loading: () => const LoadingWidget(),
              error  : (e, _) => AppErrorWidget(
                message: e.toString(),
                onRetry: () => ref.invalidate(studentActiveSessionsProvider),
              ),
              data   : (sessions) {
                if (sessions.isEmpty) {
                  return const EmptyStateWidget(
                    message : 'No active sessions right now',
                    icon    : Icons.event_busy_rounded,
                    subtitle: 'Check back when your teacher starts a session',
                  );
                }
                return ListView.separated(
                  shrinkWrap    : true,
                  physics       : const NeverScrollableScrollPhysics(),
                  itemCount     : sessions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder   : (context, i) {
                    final s = sessions[i];
                    final alreadyMarked = s['already_marked'] == true;
                    return Container(
                      decoration: BoxDecoration(
                        color       : AppColors.cardBg,
                        borderRadius: BorderRadius.circular(14),
                        border      : Border.all(color: AppColors.borderColor),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                width: 4,
                                color: alreadyMarked ? AppColors.primaryLight : AppColors.success,
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      Container(
                                        width : 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color : alreadyMarked
                                              ? AppColors.primaryLight
                                              : AppColors.success,
                                          shape : BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              s['subject_name']?.toString() ?? 'Subject',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize  : 15,
                                                color     : AppColors.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Teacher: ${s['teacher_name'] ?? "N/A"} · Room: ${s['room_name'] ?? "N/A"}',
                                              style: const TextStyle(
                                                color  : AppColors.textSecondary,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (alreadyMarked)
                                        ElevatedButton.icon(
                                          onPressed: null,
                                          icon : const Icon(Icons.check_circle_outline, size: 16),
                                          label: const Text('Marked'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColors.success.withOpacity(0.1),
                                            foregroundColor : AppColors.success,
                                            disabledBackgroundColor: AppColors.success.withOpacity(0.1),
                                            disabledForegroundColor: AppColors.success,
                                            padding: const EdgeInsets.symmetric(horizontal: 12),
                                            minimumSize: const Size(0, 36),
                                          ),
                                        )
                                      else
                                        ElevatedButton(
                                          onPressed: () {
                                            context.push(
                                              '/student/mark-attendance',
                                              extra: s,
                                            );
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColors.success,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            padding: const EdgeInsets.symmetric(horizontal: 16),
                                            minimumSize: const Size(0, 36),
                                          ),
                                          child: const Text('Mark →'),
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
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Color _pctColor(double pct) {
    if (pct >= 75) return AppColors.success;
    if (pct >= 60) return AppColors.warning;
    return AppColors.danger;
  }
}
