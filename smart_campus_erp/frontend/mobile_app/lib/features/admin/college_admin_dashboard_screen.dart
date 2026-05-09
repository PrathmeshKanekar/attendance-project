import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/layout/app_layout.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/stat_card.dart';
import '../../core/widgets/loading_widget.dart';
import '../../core/providers/dashboard_provider.dart';

class CollegeAdminDashboardScreen extends ConsumerWidget {
  const CollegeAdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(dashboardSummaryProvider);

    return AppLayout(
      title: 'College Admin',
      child: Scaffold(
        appBar: AppBar(
          title: const Text('College Admin Dashboard'),
        ),
        body: summaryAsync.when(
          loading: () => const Center(child: LoadingWidget()),
          error: (err, stack) => Center(child: Text('Error loading metrics: $err')),
          data: (data) => SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Welcome, College Admin',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Oversee departments, academic years, courses, and system users.',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),
                GridView.count(
                  crossAxisCount: MediaQuery.of(context).size.width > 600 ? 3 : 1,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.5,
                  children: [
                    StatCard(
                      label: 'Total Departments',
                      value: data.departmentsCount.toString(),
                      icon: Icons.business,
                      accentColor: AppColors.primaryLight,
                    ),
                    StatCard(
                      label: 'Enrolled Students',
                      value: data.studentsCount.toString(),
                      icon: Icons.school,
                      accentColor: AppColors.accent,
                    ),
                    StatCard(
                      label: 'Staff Members',
                      value: data.staffCount.toString(),
                      icon: Icons.people,
                      accentColor: AppColors.success,
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                const Text(
                  'Departmental Attendance Snapshot',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 4,
                    separatorBuilder: (context, index) => const Divider(),
                    itemBuilder: (context, index) {
                      final depts = [
                        {'name': 'Computer Science', 'pct': '88%', 'color': AppColors.primaryLight},
                        {'name': 'Mechanical Eng.', 'pct': '76%', 'color': AppColors.success},
                        {'name': 'Electrical Eng.', 'pct': '81%', 'color': AppColors.accent},
                        {'name': 'Information Tech.', 'pct': '91%', 'color': AppColors.warning},
                      ];
                      final d = depts[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: (d['color'] as Color).withOpacity(0.12),
                          child: Text((d['name'] as String)[0], style: TextStyle(color: d['color'] as Color, fontWeight: FontWeight.bold)),
                        ),
                        title: Text(d['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: const Text('Regular Schedule'),
                        trailing: Text(
                          d['pct'] as String,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primaryLight),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
