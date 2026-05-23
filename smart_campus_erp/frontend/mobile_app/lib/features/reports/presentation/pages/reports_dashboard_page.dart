import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:smart_campus_app/core/constants/app_colors.dart';
import 'package:smart_campus_app/core/network/api_client.dart';
import '../cubit/reports_cubit.dart';
import '../widgets/analytics_card.dart';
import '../widgets/attendance_line_chart.dart';
import '../../domain/entities/report_data.dart';

class ReportsDashboardPage extends ConsumerWidget {
  const ReportsDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(apiClientProvider);

    return BlocProvider(
      create: (_) => ReportsCubit(api)..loadDashboard(),
      child: const _ReportsView(),
    );
  }
}

class _ReportsView extends StatelessWidget {
  const _ReportsView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        backgroundColor: AppColors.bgPrimary,
        title: const Text('Reports & Analytics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () =>
                context.read<ReportsCubit>().loadDashboard(),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: BlocBuilder<ReportsCubit, ReportsState>(
        builder: (context, state) {
          if (state is ReportsLoading) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading reports...'),
                ],
              ),
            );
          }

          if (state is ReportsError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: AppColors.danger, size: 56),
                    const SizedBox(height: 16),
                    Text(
                      state.message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () =>
                          context.read<ReportsCubit>().loadDashboard(),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (state is ReportsLoaded) {
            return _buildContent(context, state);
          }

          return const SizedBox();
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, ReportsLoaded state) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Partial load warning ─────────────────────────────────────
          if (state.warningMessage != null)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.warning.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: AppColors.warning, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.warningMessage!,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.warning),
                    ),
                  ),
                ],
              ),
            ),

          // ── Summary KPI cards ────────────────────────────────────────
          if (state.summaryCards.isNotEmpty) ...[
            const Text('Overview',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.6,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: state.summaryCards.length,
              itemBuilder: (ctx, i) {
                final card = state.summaryCards[i];
                return AnalyticsCard(
                  summary: ReportSummary(
                    title: card['title']?.toString() ?? '',
                    value: card['value']?.toString() ?? '0',
                    trend: (card['trend'] as num? ?? 0.0).toDouble(),
                    isPositive: card['is_positive'] as bool? ?? true,
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
          ] else ...[
            // Empty summary state
            _EmptySection(
              icon: Icons.analytics_outlined,
              message: 'No summary data available yet.\n'
                  'Create sessions and mark attendance to see stats.',
            ),
            const SizedBox(height: 24),
          ],

          // ── Trends chart ─────────────────────────────────────────────
          const Text('Attendance Trend (Last 30 Days)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (state.trends.isNotEmpty)
            AttendanceLineChart(
              data: state.trends
                  .map((e) => ChartDataPoint(
                        e['date']?.toString() ?? '',
                        (e['percentage'] as num? ?? 0.0).toDouble(),
                      ))
                  .toList(),
            )
          else
            _EmptySection(
              icon: Icons.show_chart_rounded,
              message: 'No trend data for the last 30 days.',
              height: 160,
            ),

          const SizedBox(height: 24),

          // ── Detailed data table ──────────────────────────────────────
          if (state.detailedData.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  state.activeReportType == 'defaulters'
                      ? 'Defaulters List'
                      : state.activeReportType == 'overview'
                          ? 'Subject-wise Overview'
                          : 'Student Attendance Detail',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${state.detailedData.length} records',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _DetailTable(
                data: state.detailedData,
                type: state.activeReportType),
          ],

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EMPTY SECTION
// ─────────────────────────────────────────────────────────────────────────────
class _EmptySection extends StatelessWidget {
  final IconData icon;
  final String message;
  final double height;
  const _EmptySection(
      {required this.icon, required this.message, this.height = 120});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.bgSecondary.withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon,
              size: 36,
              color: AppColors.textSecondary.withOpacity(0.4)),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: AppColors.textSecondary.withOpacity(0.6),
                fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DETAIL TABLE — adapts columns based on report type
// ─────────────────────────────────────────────────────────────────────────────
class _DetailTable extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final String type;
  const _DetailTable({required this.data, required this.type});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Theme(
        data: Theme.of(context)
            .copyWith(dividerColor: AppColors.borderColor),
        child: DataTable(
          headingRowColor:
              MaterialStateProperty.all(AppColors.bgSecondary),
          columnSpacing: 20,
          columns: _buildColumns(),
          rows: data.map((row) => _buildRow(row)).toList(),
        ),
      ),
    );
  }

  List<DataColumn> _buildColumns() {
    if (type == 'overview') {
      return const [
        DataColumn(label: Text('Subject')),
        DataColumn(label: Text('Division')),
        DataColumn(label: Text('Students')),
        DataColumn(label: Text('At Risk')),
        DataColumn(label: Text('Avg %')),
      ];
    }
    // attendance & defaulters — student rows
    return const [
      DataColumn(label: Text('Roll')),
      DataColumn(label: Text('Name')),
      DataColumn(label: Text('PRN')),
      DataColumn(label: Text('Present')),
      DataColumn(label: Text('Total')),
      DataColumn(label: Text('%')),
    ];
  }

  DataRow _buildRow(Map<String, dynamic> row) {
    if (type == 'overview') {
      final avg = (row['avg_percentage'] as num? ?? 0.0).toDouble();
      return DataRow(cells: [
        DataCell(Text(row['subject_name']?.toString() ?? '')),
        DataCell(Text(row['division']?.toString() ?? '')),
        DataCell(Text('${row['total_students'] ?? 0}')),
        DataCell(Text(
          '${row['at_risk_count'] ?? 0}',
          style: const TextStyle(color: AppColors.danger),
        )),
        DataCell(Text(
          '${avg.toStringAsFixed(1)}%',
          style: TextStyle(
            color: avg >= 75 ? AppColors.success : AppColors.danger,
            fontWeight: FontWeight.bold,
          ),
        )),
      ]);
    }

    final pct = (row['percentage'] as num? ?? 0.0).toDouble();
    final atRisk = pct < 75;
    return DataRow(
      color: atRisk
          ? MaterialStateProperty.all(AppColors.danger.withOpacity(0.04))
          : null,
      cells: [
        DataCell(Text(row['roll_number']?.toString() ?? '-')),
        DataCell(Text(row['student_name']?.toString() ?? '')),
        DataCell(Text(row['prn']?.toString() ?? '')),
        DataCell(Text('${row['present'] ?? 0}')),
        DataCell(Text('${row['total_sessions'] ?? 0}')),
        DataCell(Text(
          '${pct.toStringAsFixed(1)}%',
          style: TextStyle(
            color: atRisk ? AppColors.danger : AppColors.success,
            fontWeight: FontWeight.bold,
          ),
        )),
      ],
    );
  }
}