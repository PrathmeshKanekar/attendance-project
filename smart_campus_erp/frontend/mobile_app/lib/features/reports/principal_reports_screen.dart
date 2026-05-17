import 'dart:io';
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
import '../../core/widgets/stat_card.dart';
import 'report_providers.dart';

class PrincipalReportsScreen extends ConsumerStatefulWidget {
  const PrincipalReportsScreen({super.key});

  @override
  ConsumerState<PrincipalReportsScreen> createState() => _PrincipalReportsScreenState();
}

class _PrincipalReportsScreenState extends ConsumerState<PrincipalReportsScreen> {
  bool _isDownloading = false;

  Future<void> _downloadFile(String type, String allocId, String subjectName) async {
    setState(() => _isDownloading = true);

    try {
      final api = ref.read(apiClientProvider);
      final endpoint = type == 'pdf' ? '/api/reports/download/pdf/' : '/api/reports/download/excel/';
      final queryParams = {
        'allocation_id': allocId,
        'start_date'   : DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 90))),
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
      final fileName = 'college_report_${subjectName.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.$extension';
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
    final overviewAsync = ref.watch(collegeOverviewProvider);

    return AppLayout(
      title: 'College Analytics',
      actions: [
        if (_isDownloading)
          const Center(child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          ))
        else
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(collegeOverviewProvider),
          ),
      ],
      child: overviewAsync.when(
        loading: () => const LoadingWidget(message: 'Loading college analytics...'),
        error: (e, _) => AppErrorWidget(
          message: e.toString(),
          onRetry: () => ref.invalidate(collegeOverviewProvider),
        ),
        data: (data) {
          final overview = data['overview'];
          final subjects = data['subjects'] as List;

          if (subjects.isEmpty) {
            return const EmptyStateWidget(
              message: 'No data available',
              icon: Icons.analytics_outlined,
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Stat Cards ────────────────────────────────
                GridView.count(
                  crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.2,
                  children: [
                    StatCard(
                      label: 'Subjects',
                      value: overview['total_subjects'].toString(),
                      icon: Icons.menu_book_rounded,
                      accentColor: AppColors.primaryLight,
                    ),
                    StatCard(
                      label: 'Students',
                      value: overview['total_students'].toString(),
                      icon: Icons.people_outline_rounded,
                      accentColor: AppColors.accent,
                    ),
                    StatCard(
                      label: 'At Risk',
                      value: overview['total_at_risk'].toString(),
                      icon: Icons.warning_amber_rounded,
                      accentColor: AppColors.danger,
                    ),
                    StatCard(
                      label: 'College Avg',
                      value: '${overview['college_avg_pct']}%',
                      icon: Icons.bar_chart_rounded,
                      accentColor: (overview['college_avg_pct'] as num) >= 75 
                          ? AppColors.success : AppColors.warning,
                    ),
                  ],
                ),

                const SizedBox(height: 32),
                const Text(
                  'Subject-wise Performance',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // ── Subject List ─────────────────────────────
                ...subjects.map((s) => _SubjectOverviewCard(
                  subject: s,
                  onDownload: (type) => _downloadFile(type, s['allocation_id'], s['subject_name']),
                )),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SubjectOverviewCard extends StatelessWidget {
  final Map<String, dynamic> subject;
  final Function(String type) onDownload;
  const _SubjectOverviewCard({required this.subject, required this.onDownload});

  @override
  Widget build(BuildContext context) {
    final avg = (subject['avg_percentage'] as num).toDouble();
    final atRisk = subject['at_risk_count'];
    
    final color = avg >= 75 ? AppColors.success 
        : avg >= 60 ? AppColors.warning : AppColors.danger;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(color: color, width: 4),
          top: const BorderSide(color: AppColors.borderColor),
          right: const BorderSide(color: AppColors.borderColor),
          bottom: const BorderSide(color: AppColors.borderColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${subject['subject_name']} (${subject['subject_code']})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    Text(
                      'Division ${subject['division']} · Year ${subject['year']}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${avg.toStringAsFixed(1)}%',
                    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const Text(
                    'Average',
                    style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _MiniStat(label: 'Students', value: subject['total_students'].toString()),
              const SizedBox(width: 16),
              _MiniStat(
                label: 'At Risk', 
                value: atRisk.toString(), 
                color: atRisk > 0 ? AppColors.danger : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: avg / 100,
              backgroundColor: AppColors.bgSecondary,
              color: color,
              minHeight: 6,
            ),
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => onDownload('pdf'),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18, color: AppColors.danger),
                label: const Text('PDF', style: TextStyle(fontSize: 12, color: AppColors.danger)),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => onDownload('excel'),
                icon: const Icon(Icons.table_view_outlined, size: 18, color: AppColors.success),
                label: const Text('Excel', style: TextStyle(fontSize: 12, color: AppColors.success)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label, value;
  final Color? color;
  const _MiniStat({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        Text(
          value,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }
}
