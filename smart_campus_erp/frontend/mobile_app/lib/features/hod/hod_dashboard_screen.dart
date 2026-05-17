import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/layout/app_layout.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/stat_card.dart';

final hodStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final api = ref.read(apiClientProvider);
  final res = await api.get('/api/reports/hod-summary/');
  return Map<String, dynamic>.from(res.data);
});

class HodDashboardScreen extends ConsumerWidget {
  const HodDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(hodStatsProvider);

    return AppLayout(
      title: 'Department Dashboard',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Departmental Insights',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 24),
            
            statsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error: $e'),
              data: (stats) => Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: StatCard(
                          label: 'Overall Attendance',
                          value: '${stats['avg_attendance']}%',
                          icon: Icons.show_chart_rounded,
                          accentColor: AppColors.primaryLight,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: StatCard(
                          label: 'Active Classes',
                          value: '${stats['active_classes']}',
                          icon: Icons.class_rounded,
                          accentColor: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildFacultyList(stats['faculty_performance'] ?? []),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFacultyList(List faculty) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Faculty Performance',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 12),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: faculty.length,
          separatorBuilder: (_, __) => const Divider(),
          itemBuilder: (context, i) {
            final f = faculty[i];
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.withOpacity(0.1),
                child: Text(f['name'][0], style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
              ),
              title: Text(f['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${f['subjects_count']} Subjects · ${f['avg_attendance']}% Avg.'),
              trailing: Icon(
                Icons.circle,
                size: 12,
                color: (f['avg_attendance'] as num) > 80 ? Colors.green : Colors.orange,
              ),
            );
          },
        ),
      ],
    );
  }
}
