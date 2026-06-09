import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/layout/app_layout.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/network/api_client.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/stat_card.dart';
import '../../core/widgets/loading_widget.dart';
import '../../core/widgets/error_widget.dart';

final adminStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final api = ref.read(apiClientProvider);
  int totalUsers = 0;
  int pendingCount = 0;
  int departmentsCount = 0;
  int subjectsCount = 0;

  try {
    final res = await api.get('/api/auth/users/');
    final users = res.data['users'] as List? ?? [];
    totalUsers = users.length;
    pendingCount = users.where((u) => u['is_approved'] == false).length;
  } catch (_) {}

  try {
    final res = await api.get('/api/departments/');
    departmentsCount = (res.data is List ? res.data : []).length;
  } catch (_) {}

  int coursesCount = 0;
  try {
    final res = await api.get('/api/courses/');
    coursesCount = (res.data is List ? res.data : []).length;
  } catch (_) {}

  int pendingStudentsCount = 0;
  try {
    final res = await api.get('/api/lab-assistant/pending-students/');
    pendingStudentsCount = (res.data is List ? res.data : []).length;
  } catch (_) {}

  return {
    'total_users': totalUsers,
    'departments': departmentsCount,
    'subjects': subjectsCount,
    'pending': pendingCount,
    'courses': coursesCount,
    'pending_students': pendingStudentsCount,
  };
});

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    if (authState is! AuthSuccess) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final user = authState.user;
    final statsAsync = ref.watch(adminStatsProvider);
    final isLab = user.role == 'lab_assistant';
    final isAdmin = user.role == 'college_admin';

    return AppLayout(
      title: isAdmin ? 'Academic Master' : 'Lab Administration',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // SECTION 1 — Greeting
            Text(
              'Good morning, ${user.firstName}! 👋',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${user.collegeName ?? ""}  ·  ${isAdmin ? "Academic Management" : "Technical Staff"}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 24),

            // SECTION 2 — Stat cards
            statsAsync.when(
              loading: () => const LoadingWidget(message: 'Loading stats...'),
              error: (e, _) => AppErrorWidget(
                message: e.toString(),
                onRetry: () => ref.invalidate(adminStatsProvider),
              ),
              data: (stats) => GridView.count(
                crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.2,
                children: [
                  if (isAdmin) ...[
                    StatCard(
                      label: 'Departments',
                      value: '${stats['departments']}',
                      icon: Icons.apartment_rounded,
                      accentColor: AppColors.primaryLight,
                      subtitle: 'Active branches',
                    ),
                    StatCard(
                      label: 'Courses',
                      value: '${stats['courses']}',
                      icon: Icons.school_rounded,
                      accentColor: AppColors.accent,
                      subtitle: 'Academic programs',
                    ),
                  ],
                  if (isLab) ...[
                    StatCard(
                      label: 'Subjects',
                      value: '${stats['subjects']}',
                      icon: Icons.menu_book_rounded,
                      accentColor: AppColors.success,
                      subtitle: 'Total registered',
                    ),
                    StatCard(
                      label: 'Enrollments',
                      value: '${stats['total_users']}', // Simple placeholder
                      icon: Icons.people_rounded,
                      accentColor: AppColors.primaryLight,
                      subtitle: 'Student pool',
                    ),
                    StatCard(
                      label: 'Pending Approvals',
                      value: '${stats['pending_students']}',
                      icon: Icons.pending_actions_rounded,
                      accentColor: AppColors.warning,
                      subtitle: 'Awaiting review',
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 28),

            // SECTION 3 — Quick actions grid
            const Text(
              'Quick Actions',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),

            GridView.count(
              crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.3,
              children: [
                // COLLEGE ADMIN ONLY actions — Restricted to Academic Master & Users
                if (isAdmin) ...[
                  const _QuickActionCard(
                    label: 'Academic Year',
                    icon: Icons.event_note_rounded,
                    color: AppColors.primaryLight,
                    route: '/admin/academic-years',
                  ),
                  const _QuickActionCard(
                    label: 'Departments',
                    icon: Icons.apartment_rounded,
                    color: AppColors.accent,
                    route: '/admin/departments',
                  ),
                  const _QuickActionCard(
                    label: 'Courses',
                    icon: Icons.school_rounded,
                    color: AppColors.warning,
                    route: '/admin/courses',
                  ),
                  const _QuickActionCard(
                    label: 'Add User',
                    icon: Icons.person_add_rounded,
                    color: AppColors.success,
                    route: '/admin/users/add',
                  ),
                ],

                // LAB ASSISTANT ONLY actions — Virtual Rooms & Academic Structure
                if (isLab) ...[
                  const _QuickActionCard(
                    label: 'Virtual Rooms',
                    icon: Icons.sensor_door_rounded,
                    color: AppColors.success,
                    route: '/admin/virtual-rooms',
                  ),
                  const _QuickActionCard(
                    label: 'Room Validation',
                    icon: Icons.science_rounded,
                    color: AppColors.accent,
                    route: '/admin/virtual-rooms/validate',
                  ),
                  const _QuickActionCard(
                    label: 'Subjects',
                    icon: Icons.menu_book_rounded,
                    color: AppColors.warning,
                    route: '/admin/subjects',
                  ),
                  const _QuickActionCard(
                    label: 'Divisions',
                    icon: Icons.groups_rounded,
                    color: AppColors.accent,
                    route: '/admin/divisions',
                  ),
                  const _QuickActionCard(
                    label: 'Allocations',
                    icon: Icons.assignment_rounded,
                    color: AppColors.primaryLight,
                    route: '/admin/allocations',
                  ),
                  const _QuickActionCard(
                    label: 'Enrollments',
                    icon: Icons.how_to_reg_rounded,
                    color: AppColors.success,
                    route: '/admin/enrollments',
                  ),
                  const _QuickActionCard(
                    label: 'Face Register',
                    icon: Icons.face_retouching_natural_rounded,
                    color: AppColors.accent,
                    route: '/admin/face-register',
                  ),
                  const _QuickActionCard(
                    label: 'Student Approvals',
                    icon: Icons.check_circle_rounded,
                    color: AppColors.warning,
                    route: '/admin/approvals',
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final String route;

  const _QuickActionCard({
    required this.label,
    required this.icon,
    required this.color,
    required this.route,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push(route),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
