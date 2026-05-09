import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/layout/app_layout.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/network/api_client.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/stat_card.dart';
import '../../core/widgets/loading_widget.dart';
import '../../core/widgets/error_widget.dart';
import '../../core/widgets/empty_state_widget.dart';

final hodStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final api = ref.read(apiClientProvider);
  int facultyCount = 0;
  int subjectCount = 0;
  int studentCount = 0;
  int defaulterCount = 0;

  try {
    final res = await api.get('/api/auth/users/', params: {'role': 'teacher'});
    facultyCount = (res.data['users'] as List? ?? []).length;
  } catch (_) {}

  try {
    final res = await api.get('/api/subjects/');
    subjectCount = (res.data is List ? res.data : []).length;
  } catch (_) {}

  try {
    final res = await api.get('/api/auth/users/', params: {'role': 'student'});
    studentCount = (res.data['users'] as List? ?? []).length;
  } catch (_) {}

  try {
    final res = await api.get('/api/reports/defaulters/');
    defaulterCount = (res.data is List ? res.data : []).length;
  } catch (_) {}

  return {
    'faculty_members': facultyCount,
    'dept_subjects': subjectCount,
    'total_students': studentCount,
    'below_75': defaulterCount,
  };
});

final hodSubjectsProvider = FutureProvider<List>((ref) async {
  final api = ref.read(apiClientProvider);
  try {
    final res = await api.get('/api/subjects/');
    return res.data is List ? res.data : [];
  } catch (_) {
    return [];
  }
});

class HodDashboardScreen extends ConsumerWidget {
  const HodDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    if (authState is! AuthSuccess) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final user = authState.user;
    final statsAsync = ref.watch(hodStatsProvider);
    final subjectsAsync = ref.watch(hodSubjectsProvider);

    return AppLayout(
      title: 'HOD Dashboard',
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
              '${user.collegeName ?? ""}  ·  Head of Department Mode',
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
                onRetry: () => ref.invalidate(hodStatsProvider),
              ),
              data: (stats) => GridView.count(
                crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.2,
                children: [
                  StatCard(
                    label: 'Faculty Members',
                    value: '${stats['faculty_members']}',
                    icon: Icons.person_search_rounded,
                    accentColor: AppColors.primaryLight,
                    subtitle: 'Total department faculty',
                  ),
                  StatCard(
                    label: 'Dept Subjects',
                    value: '${stats['dept_subjects']}',
                    icon: Icons.menu_book_rounded,
                    accentColor: AppColors.accent,
                    subtitle: 'Assigned courses',
                  ),
                  StatCard(
                    label: 'Total Students',
                    value: '${stats['total_students']}',
                    icon: Icons.school_rounded,
                    accentColor: AppColors.success,
                    subtitle: 'Enrolled in department',
                  ),
                  StatCard(
                    label: 'Below 75%',
                    value: '${stats['below_75']}',
                    icon: Icons.warning_amber_rounded,
                    accentColor: AppColors.danger,
                    subtitle: 'Defaulters count',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // SECTION 3 — Department subjects list
            const Text(
              'Department Subjects',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),

            subjectsAsync.when(
              loading: () => const LoadingWidget(),
              error: (e, _) => AppErrorWidget(
                message: e.toString(),
                onRetry: () => ref.invalidate(hodSubjectsProvider),
              ),
              data: (subjects) {
                if (subjects.isEmpty) {
                  return const EmptyStateWidget(
                    message: 'No subjects created yet',
                    icon: Icons.menu_book_rounded,
                    subtitle: 'Create subjects in department management',
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: subjects.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final s = subjects[i] as Map<String, dynamic>;
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.cardBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.borderColor),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s['name']?.toString() ?? 'Subject',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Code: ${s['code'] ?? ""}  ·  Year: ${s['year_of_study'] ?? ""} · Sem: ${s['semester'] ?? ""}',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
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
}
