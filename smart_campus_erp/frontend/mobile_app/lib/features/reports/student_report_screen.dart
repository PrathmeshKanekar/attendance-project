import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/layout/app_layout.dart';
import '../../core/widgets/error_widget.dart';
import '../../core/widgets/loading_widget.dart';
import '../../core/widgets/empty_state_widget.dart';
import 'report_providers.dart';

class StudentReportScreen extends ConsumerWidget {
  const StudentReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(studentMyAttendanceProvider);

    return AppLayout(
      title  : 'My Attendance Report',
      actions: [
        IconButton(
          icon     : const Icon(Icons.refresh_rounded),
          onPressed: () => ref.invalidate(studentMyAttendanceProvider),
          tooltip  : 'Refresh',
        ),
      ],
      child: async.when(
        loading: () => const LoadingWidget(message: 'Loading your report...'),
        error  : (e, _) => AppErrorWidget(
          message: e.toString(),
          onRetry: () => ref.invalidate(studentMyAttendanceProvider),
        ),
        data   : (subjects) {
          if (subjects.isEmpty) {
            return const EmptyStateWidget(
              message : 'No attendance data yet',
              icon    : Icons.analytics_outlined,
              subtitle: 'Attendance data will appear after sessions end',
            );
          }

          // ── Compute overall stats ────────────────────
          final totalSubjects = subjects.length;
          final atRisk        = subjects.where(
            (s) => s['is_at_risk'] == true,
          ).length;
          final avgPct = subjects.fold<double>(
            0.0,
            (sum, s) => sum + (s['percentage'] as num).toDouble(),
          ) / totalSubjects;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child  : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── Overall donut chart card ─────────────
                Container(
                  padding   : const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color       : AppColors.cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border      : Border.all(color: AppColors.borderColor),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Overall Attendance',
                        style: TextStyle(
                          fontSize  : 16,
                          fontWeight: FontWeight.w700,
                          color     : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Donut chart
                      SizedBox(
                        height: 200,
                        child : Stack(
                          alignment: Alignment.center,
                          children : [
                            PieChart(
                              PieChartData(
                                sectionsSpace: 3,
                                centerSpaceRadius: 60,
                                sections: [
                                  PieChartSectionData(
                                    value     : avgPct,
                                    color     : _pctColor(avgPct),
                                    title     : '',
                                    radius    : 40,
                                  ),
                                  PieChartSectionData(
                                    value     : 100 - avgPct,
                                    color     : AppColors.bgSecondary,
                                    title     : '',
                                    radius    : 40,
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${avgPct.toStringAsFixed(1)}%',
                                  style: TextStyle(
                                    fontSize  : 26,
                                    fontWeight: FontWeight.w800,
                                    color     : _pctColor(avgPct),
                                  ),
                                ),
                                const Text(
                                  'Average',
                                  style: TextStyle(
                                    color  : AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Legend row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _LegendItem(
                            color: AppColors.primaryLight,
                            label: '$totalSubjects Subjects',
                          ),
                          _LegendItem(
                            color: AppColors.danger,
                            label: '$atRisk At Risk',
                          ),
                          _LegendItem(
                            color: AppColors.success,
                            label: '${totalSubjects - atRisk} Safe',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── Per subject bar chart ─────────────────
                if (subjects.isNotEmpty) ...[
                  const Text(
                    'Subject-wise Attendance',
                    style: TextStyle(
                      fontSize  : 17,
                      fontWeight: FontWeight.w700,
                      color     : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height    : 220,
                    padding   : const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color       : AppColors.cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border      : Border.all(color: AppColors.borderColor),
                    ),
                    child: BarChart(
                      BarChartData(
                        alignment      : BarChartAlignment.spaceAround,
                        maxY           : 100,
                        barTouchData   : BarTouchData(
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipColor: (_) => AppColors.dark,
                            getTooltipItem: (group, gI, rod, rI) =>
                                BarTooltipItem(
                              '${subjects[gI]['subject_code']}\n'
                              '${rod.toY.toStringAsFixed(1)}%',
                              const TextStyle(
                                color: Colors.white, fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                        titlesData: FlTitlesData(
                          show: true,
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles   : true,
                              reservedSize : 28,
                              getTitlesWidget: (val, meta) {
                                final idx = val.toInt();
                                if (idx < 0 || idx >= subjects.length) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child  : Text(
                                    subjects[idx]['subject_code']
                                        .toString()
                                        .split('')
                                        .take(4)
                                        .join(),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color   : AppColors.textSecondary,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles   : true,
                              reservedSize : 36,
                              interval     : 25,
                              getTitlesWidget: (val, meta) => Text(
                                '${val.toInt()}%',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color   : AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                          topTitles  : const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                        gridData: FlGridData(
                          show             : true,
                          drawVerticalLine : false,
                          horizontalInterval: 25,
                          getDrawingHorizontalLine: (val) => const FlLine(
                            color: AppColors.borderColor,
                            strokeWidth: 1,
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        barGroups : subjects.asMap().entries.map((e) {
                          final pct = (e.value['percentage'] as num)
                              .toDouble();
                          return BarChartGroupData(
                            x       : e.key,
                            barRods : [
                              BarChartRodData(
                                toY      : pct,
                                color    : _pctColor(pct),
                                width    : 18,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(6),
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // ── Per subject cards ─────────────────────
                const Text(
                  'Subject Details',
                  style: TextStyle(
                    fontSize  : 17,
                    fontWeight: FontWeight.w700,
                    color     : AppColors.textPrimary,
                    ),
                  ),
                const SizedBox(height: 12),

                ...subjects.map((s) => _SubjectAttendanceCard(subject: s)),
              ],
            ),
          );
        },
      ),
    );
  }

  Color _pctColor(double pct) {
    if (pct >= 75) return AppColors.success;
    if (pct >= 60) return AppColors.warning;
    return AppColors.danger;
  }
}


// ── Per-subject attendance card ────────────────────────────
class _SubjectAttendanceCard extends StatelessWidget {
  final Map<String, dynamic> subject;
  const _SubjectAttendanceCard({required this.subject});

  @override
  Widget build(BuildContext context) {
    final pct      = (subject['percentage'] as num).toDouble();
    final isAtRisk = subject['is_at_risk'] == true;
    final color    = pct >= 75
        ? AppColors.success
        : pct >= 60 ? AppColors.warning : AppColors.danger;

    return Container(
      margin    : const EdgeInsets.only(bottom: 12),
      padding   : const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color       : AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border      : Border(
          left  : BorderSide(color: color, width: 4),
          top   : const BorderSide(color: AppColors.borderColor),
          right : const BorderSide(color: AppColors.borderColor),
          bottom: const BorderSide(color: AppColors.borderColor),
        ),
      ),
      child: Row(
        children: [
          // Progress ring
          SizedBox(
            width : 56, height: 56,
            child : Stack(
              alignment: Alignment.center,
              children : [
                CircularProgressIndicator(
                  value          : pct / 100,
                  backgroundColor: AppColors.bgSecondary,
                  color          : color,
                  strokeWidth    : 5,
                ),
                Text(
                  '${pct.toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize  : 11,
                    fontWeight: FontWeight.bold,
                    color     : color,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 14),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        subject['subject_name']?.toString() ?? '',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize  : 14,
                          color     : AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (isAtRisk)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color       : AppColors.danger.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(6),
                          border      : Border.all(
                            color: AppColors.danger.withOpacity(0.30),
                          ),
                        ),
                        child: const Text(
                          '⚠ At Risk',
                          style: TextStyle(
                            color    : AppColors.danger,
                            fontSize : 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${subject['subject_code']} · '
                  'Div ${subject['division_name']}',
                  style: const TextStyle(
                    color  : AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6),
                // Attended / Total row
                Row(
                  children: [
                    _StatPill(
                      label: '${subject['present']}',
                      sub  : 'Attended',
                      color: AppColors.success,
                    ),
                    const SizedBox(width: 8),
                    _StatPill(
                      label: '${subject['absent']}',
                      sub  : 'Missed',
                      color: AppColors.danger,
                    ),
                    const SizedBox(width: 8),
                    _StatPill(
                      label: '${subject['total_sessions']}',
                      sub  : 'Total',
                      color: AppColors.primaryLight,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label, sub;
  final Color  color;
  const _StatPill({
    required this.label,
    required this.sub,
    required this.color,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color       : color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(
            color: color, fontWeight: FontWeight.bold, fontSize: 13,
          )),
          Text(sub, style: const TextStyle(
            color: AppColors.textSecondary, fontSize: 9,
          )),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color; final String label;
  const _LegendItem({required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12, height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(
          fontSize: 12, color: AppColors.textSecondary,
        )),
      ],
    );
  }
}
