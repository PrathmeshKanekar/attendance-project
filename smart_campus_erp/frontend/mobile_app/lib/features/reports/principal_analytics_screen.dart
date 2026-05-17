import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/layout/app_layout.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/stat_card.dart';

final principalAnalyticsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final api = ref.read(apiClientProvider);
  final res = await api.get('/api/reports/principal-summary/');
  return Map<String, dynamic>.from(res.data);
});

class PrincipalAnalyticsScreen extends ConsumerWidget {
  const PrincipalAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(principalAnalyticsProvider);

    return AppLayout(
      title: 'Institutional Analytics',
      child: analyticsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (data) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle('Campus Attendance Overview'),
              const SizedBox(height: 16),
              _buildAttendanceChart(data['attendance_trend'] ?? []),
              const SizedBox(height: 32),
              
              _buildSectionTitle('Departmental Performance'),
              const SizedBox(height: 16),
              _buildDepartmentGrid(data['department_stats'] ?? []),
              const SizedBox(height: 32),
              
              _buildSectionTitle('Critical Alerts'),
              const SizedBox(height: 16),
              _buildAlertsList(data['alerts'] ?? []),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
    );
  }

  Widget _buildAttendanceChart(List trend) {
    return Container(
      height: 250,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: List.generate(trend.length, (i) => FlSpot(i.toDouble(), (trend[i]['value'] as num).toDouble())),
              isCurved: true,
              color: AppColors.primaryLight,
              barWidth: 4,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: AppColors.primaryLight.withOpacity(0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDepartmentGrid(List stats) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.5,
      ),
      itemCount: stats.length,
      itemBuilder: (context, i) {
        final d = stats[i];
        return StatCard(
          label: d['name'],
          value: '${d['attendance_pct']}%',
          icon: Icons.business_rounded,
          accentColor: (d['attendance_pct'] as num) > 75 ? AppColors.success : AppColors.warning,
          subtitle: '${d['student_count']} Students',
        );
      },
    );
  }

  Widget _buildAlertsList(List alerts) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: alerts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final a = alerts[i];
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.danger.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.danger.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: AppColors.danger),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a['title'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Text(a['desc'], style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
