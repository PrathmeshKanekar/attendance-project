import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/layout/app_layout.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/stat_card.dart';
import '../../core/widgets/loading_widget.dart';

final hodStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final api = ref.read(apiClientProvider);
  final res = await api.get('/api/reports/hod-summary/');
  return Map<String, dynamic>.from(res.data);
});

class HodDashboardScreen extends ConsumerWidget {
  const HodDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final statsAsync = ref.watch(hodStatsProvider);

    return AppLayout(
      title: 'Department Dashboard',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Departmental Insights',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 24),
            
            statsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 80),
                child: LoadingWidget(message: 'Gathering Departmental Statistics...'),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.danger.withOpacity(0.3)),
                    ),
                    child: Text(
                      'Reconstruction Anomaly: $e',
                      style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
              data: (stats) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth > 600;
                      return isWide
                          ? Row(
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
                            )
                          : Column(
                              children: [
                                StatCard(
                                  label: 'Overall Attendance',
                                  value: '${stats['avg_attendance']}%',
                                  icon: Icons.show_chart_rounded,
                                  accentColor: AppColors.primaryLight,
                                ),
                                const SizedBox(height: 16),
                                StatCard(
                                  label: 'Active Classes',
                                  value: '${stats['active_classes']}',
                                  icon: Icons.class_rounded,
                                  accentColor: AppColors.success,
                                ),
                              ],
                            );
                    },
                  ),
                  const SizedBox(height: 32),
                  _buildFacultyList(context, stats['faculty_performance'] ?? [], isDark),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFacultyList(BuildContext context, List faculty, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Faculty Performance',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 16),
        if (faculty.isEmpty)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: const Text('No faculty members found.'),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: faculty.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final f = faculty[i];
              final name = f['name']?.toString() ?? 'Faculty';
              final initial = name.isNotEmpty ? name[0] : 'F';
              final avgAttendance = (f['avg_attendance'] as num?)?.toDouble() ?? 0.0;
              final isGood = avgAttendance >= 80.0;

              return Container(
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCardBg : AppColors.cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? AppColors.darkBorderColor : AppColors.borderColor,
                    width: 1.2,
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.primaryLight.withOpacity(0.12),
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: AppColors.primaryLight,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  title: Text(
                    name,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${f['subjects_count']} Subjects · ${avgAttendance.toStringAsFixed(1)}% Avg.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: (isGood ? AppColors.success : AppColors.warning).withOpacity(0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.circle,
                          size: 8,
                          color: isGood ? AppColors.success : AppColors.warning,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isGood ? 'Optimal' : 'Needs Review',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isGood ? AppColors.success : AppColors.warning,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
