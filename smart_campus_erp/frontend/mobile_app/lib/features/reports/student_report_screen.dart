import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/layout/app_layout.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/error_widget.dart';
import '../../core/widgets/loading_widget.dart';
import '../../core/widgets/empty_state_widget.dart';
import 'report_providers.dart';

class StudentReportScreen extends ConsumerStatefulWidget {
  const StudentReportScreen({super.key});

  @override
  ConsumerState<StudentReportScreen> createState() => _StudentReportScreenState();
}

class _StudentReportScreenState extends ConsumerState<StudentReportScreen> {
  bool _isDownloading = false;

  Future<void> _downloadFile(String type, String allocId, String subjectCode) async {
    setState(() => _isDownloading = true);

    try {
      final api = ref.read(apiClientProvider);
      final endpoint = type == 'pdf' ? '/api/reports/download/pdf/' : '/api/reports/download/excel/';
      final queryParams = {
        'allocation_id': allocId,
        'start_date'   : '2020-01-01',
        'end_date'     : DateFormat('yyyy-MM-dd').format(DateTime.now()),
      };

      Directory? dir;
      if (Platform.isAndroid) {
        dir = Directory('/storage/emulated/0/Download');
        if (!await dir.exists()) dir = await getExternalStorageDirectory();
      } else {
        dir = await getApplicationDocumentsDirectory();
      }

      final extension = type == 'pdf' ? 'pdf' : 'xlsx';
      final fileName = 'my_attendance_${subjectCode}_${DateTime.now().millisecondsSinceEpoch}.$extension';
      final savePath = '${dir!.path}/$fileName';

      await api.download(
        endpoint,
        savePath,
        queryParameters: queryParams,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${type.toUpperCase()} downloaded successfully'),
            action: SnackBarAction(
              label: 'Open',
              onPressed: () => OpenFilex.open(savePath),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e'), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(studentMyAttendanceProvider);

    return AppLayout(
      title  : 'My Attendance Report',
      actions: [
        if (_isDownloading)
          const Center(child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          ))
        else
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

          final totalSubjects = subjects.length;
          final atRisk        = subjects.where((s) => s['is_at_risk'] == true).length;
          final avgPct = subjects.fold<double>(0.0, (sum, s) => sum + (s['percentage'] as num).toDouble()) / totalSubjects;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child  : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildOverallCard(avgPct, totalSubjects, atRisk),
                const SizedBox(height: 24),
                _buildChart(subjects),
                const SizedBox(height: 24),
                const Text(
                  'Subject Details',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 12),
                ...subjects.map((s) => _SubjectAttendanceCard(
                  subject: s,
                  onDownload: (type) => _downloadFile(type, s['allocation_id'], s['subject_code']),
                )),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildOverallCard(double avgPct, int total, int atRisk) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.borderColor),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          const Text('Academic Overview', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 24),
          SizedBox(
            height: 180,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(PieChartData(sectionsSpace: 4, centerSpaceRadius: 55, sections: [
                  PieChartSectionData(value: avgPct, color: _pctColor(avgPct), title: '', radius: 38),
                  PieChartSectionData(value: 100 - avgPct, color: AppColors.bgSecondary, title: '', radius: 38),
                ])),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('${avgPct.toStringAsFixed(1)}%', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: _pctColor(avgPct))),
                  const Text('Total Avg', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _SummaryPill(label: 'Subjects', value: '$total', color: AppColors.primary),
              _SummaryPill(label: 'Safe', value: '${total - atRisk}', color: AppColors.success),
              _SummaryPill(label: 'At Risk', value: '$atRisk', color: AppColors.danger),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChart(List subjects) {
    return Container(
      height: 220,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: BarChart(BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: 100,
        barTouchData: BarTouchData(enabled: true),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32, getTitlesWidget: (val, _) {
            final idx = val.toInt();
            if (idx < 0 || idx >= subjects.length) return const SizedBox.shrink();
            return Padding(padding: const EdgeInsets.only(top: 8), child: Text(subjects[idx]['subject_code'].toString(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary)));
          })),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (val, _) => Text('${val.toInt()}%', style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)))),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barGroups: subjects.asMap().entries.map((e) => BarChartGroupData(x: e.key, barRods: [
          BarChartRodData(toY: (e.value['percentage'] as num).toDouble(), color: _pctColor((e.value['percentage'] as num).toDouble()), width: 16, borderRadius: const BorderRadius.vertical(top: Radius.circular(6))),
        ])).toList(),
      )),
    );
  }

  Color _pctColor(double pct) {
    if (pct >= 75) return AppColors.success;
    if (pct >= 60) return AppColors.warning;
    return AppColors.danger;
  }
}

class _SummaryPill extends StatelessWidget {
  final String label, value;
  final Color color;
  const _SummaryPill({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _SubjectAttendanceCard extends StatelessWidget {
  final Map<String, dynamic> subject;
  final Function(String type) onDownload;
  const _SubjectAttendanceCard({required this.subject, required this.onDownload});

  @override
  Widget build(BuildContext context) {
    final pct = (subject['percentage'] as num).toDouble();
    final isAtRisk = subject['is_at_risk'] == true;
    final color = pct >= 75 ? AppColors.success : pct >= 60 ? AppColors.warning : AppColors.danger;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderColor),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 60, height: 60,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(value: pct / 100, backgroundColor: AppColors.bgSecondary, color: color, strokeWidth: 6),
                    Text('${pct.toStringAsFixed(0)}%', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(subject['subject_name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textPrimary))),
                        if (isAtRisk) _RiskBadge(),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('${subject['subject_code']} · Div ${subject['division_name']}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _StatPill(label: '${subject['present']}', sub: 'Present', color: AppColors.success),
                        const SizedBox(width: 12),
                        _StatPill(label: '${subject['absent']}', sub: 'Absent', color: AppColors.danger),
                        const SizedBox(width: 12),
                        _StatPill(label: '${subject['total_sessions']}', sub: 'Total', color: AppColors.primary),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1)),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _ExportButton(label: 'PDF', icon: Icons.picture_as_pdf_outlined, color: AppColors.danger, onTap: () => onDownload('pdf')),
              const SizedBox(width: 12),
              _ExportButton(label: 'Excel', icon: Icons.table_view_outlined, color: AppColors.success, onTap: () => onDownload('excel')),
            ],
          ),
        ],
      ),
    );
  }
}

class _RiskBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: AppColors.danger.withOpacity(0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.danger.withOpacity(0.2))),
      child: const Text('⚠ LOW ATTENDANCE', style: TextStyle(color: AppColors.danger, fontSize: 9, fontWeight: FontWeight.w900)),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label, sub;
  final Color color;
  const _StatPill({required this.label, required this.sub, required this.color});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 15)),
        Text(sub, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _ExportButton extends StatelessWidget {
  final String label; final IconData icon; final Color color; final VoidCallback onTap;
  const _ExportButton({required this.label, required this.icon, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(border: Border.all(color: color.withOpacity(0.2)), borderRadius: BorderRadius.circular(8)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
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
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
