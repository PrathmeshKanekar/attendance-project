import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/constants/app_colors.dart';
import '../../core/layout/app_layout.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/error_widget.dart';
import '../../core/widgets/loading_widget.dart';
import '../../core/widgets/empty_state_widget.dart';
import '../teacher/providers/teacher_providers.dart';
import 'report_providers.dart';

class TeacherReportsScreen extends ConsumerStatefulWidget {
  const TeacherReportsScreen({super.key});

  @override
  ConsumerState<TeacherReportsScreen> createState() => _TeacherReportsScreenState();
}

class _TeacherReportsScreenState extends ConsumerState<TeacherReportsScreen> {
  String? _selectedAllocationId;
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 90));
  DateTime _endDate   = DateTime.now();
  final double _threshold   = 75.0;
  bool _isDownloading = false;

  Map<String, String> get _params => {
    'allocation_id': _selectedAllocationId ?? '',
    'start_date'   : DateFormat('yyyy-MM-dd').format(_startDate),
    'end_date'     : DateFormat('yyyy-MM-dd').format(_endDate),
    'threshold'    : _threshold.toString(),
  };

  Future<void> _downloadFile(String type) async {
    if (_selectedAllocationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a subject first')),
      );
      return;
    }

    setState(() => _isDownloading = true);

    try {
      await Permission.storage.request();
      // On Android 13+, storage permission is split into photos, videos, audio.
      // For general downloads, we might need manageExternalStorage or just use path_provider's getExternalStorageDirectory.
      
      final api = ref.read(apiClientProvider);
      final endpoint = type == 'pdf' ? '/api/reports/download/pdf/' : '/api/reports/download/excel/';
      final queryParams = {
        'allocation_id': _selectedAllocationId,
        'start_date'   : DateFormat('yyyy-MM-dd').format(_startDate),
        'end_date'     : DateFormat('yyyy-MM-dd').format(_endDate),
        'threshold'    : _threshold,
      };

      final dir = await getApplicationDocumentsDirectory();
      final extension = type == 'pdf' ? 'pdf' : 'xlsx';
      final fileName = 'attendance_${DateTime.now().millisecondsSinceEpoch}.$extension';
      final savePath = '${dir.path}/$fileName';

      await api.download(
        endpoint,
        savePath,
        params: queryParams,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            debugPrint("${(received / total * 100).toStringAsFixed(0)}%");
          }
        },
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
    final allocationsAsync = ref.watch(teacherAllocationsProvider);
    final summaryAsync     = _selectedAllocationId != null 
        ? ref.watch(attendanceSummaryProvider(_params))
        : null;

    return AppLayout(
      title: 'Attendance Reports',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Filter Panel ────────────────────────────────
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppColors.borderColor),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    allocationsAsync.when(
                      data: (list) => DropdownButtonFormField<String>(
                        value: _selectedAllocationId,
                        decoration: const InputDecoration(
                          labelText: 'Select Subject',
                          prefixIcon: Icon(Icons.book_outlined),
                        ),
                        items: list.map((a) => DropdownMenuItem(
                          value: a['id'].toString(),
                          child: Text('${a['subject_name']} (${a['division_name']})'),
                        )).toList(),
                        onChanged: (val) => setState(() => _selectedAllocationId = val),
                      ),
                      loading: () => const LinearProgressIndicator(),
                      error: (e, _) => Text('Error loading subjects: $e'),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _DatePickerTile(
                            label: 'From',
                            date: _startDate,
                            onTap: () async {
                              final d = await showDatePicker(
                                context: context,
                                initialDate: _startDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now(),
                              );
                              if (d != null) setState(() => _startDate = d);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DatePickerTile(
                            label: 'To',
                            date: _endDate,
                            onTap: () async {
                              final d = await showDatePicker(
                                context: context,
                                initialDate: _endDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now(),
                              );
                              if (d != null) setState(() => _endDate = d);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _selectedAllocationId != null 
                                ? () => ref.invalidate(attendanceSummaryProvider(_params))
                                : null,
                            icon: const Icon(Icons.analytics_outlined),
                            label: const Text('View Report'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isDownloading ? null : () => _downloadFile('pdf'),
                            icon: const Icon(Icons.picture_as_pdf_outlined),
                            label: const Text('PDF'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isDownloading ? null : () => _downloadFile('excel'),
                            icon: const Icon(Icons.table_view_outlined),
                            label: const Text('Excel'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ── Summary & Results ────────────────────────────
            if (summaryAsync != null)
              summaryAsync.when(
                loading: () => const LoadingWidget(message: 'Generating summary...'),
                error: (e, _) => AppErrorWidget(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(attendanceSummaryProvider(_params)),
                ),
                data: (data) {
                  final summary = data['summary'];
                  final students = data['students'] as List;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SummaryBanner(summary: summary),
                      const SizedBox(height: 24),
                      const Text(
                        'Student Wise List',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      _StudentDataTable(students: students, threshold: _threshold),
                    ],
                  );
                },
              ),
            
            const SizedBox(height: 32),
            const Text(
              'Recent Session History',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _SessionHistoryList(allocationId: _selectedAllocationId),
          ],
        ),
      ),
    );
  }
}

class _DatePickerTile extends StatelessWidget {
  final String label;
  final DateTime date;
  final VoidCallback onTap;
  const _DatePickerTile({required this.label, required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.borderColor),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            const SizedBox(height: 2),
            Text(DateFormat('dd MMM yyyy').format(date), style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class _SummaryBanner extends StatelessWidget {
  final Map<String, dynamic> summary;
  const _SummaryBanner({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _SummaryItem(label: 'Total', value: summary['total_students'].toString()),
          _SummaryItem(label: 'Safe', value: summary['above_threshold'].toString(), color: AppColors.success),
          _SummaryItem(label: 'At Risk', value: summary['below_threshold'].toString(), color: AppColors.danger),
          _SummaryItem(label: 'Avg', value: '${summary['average_percentage']}%', color: AppColors.primaryLight),
        ],
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String label, value;
  final Color? color;
  const _SummaryItem({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color ?? AppColors.textPrimary)),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _StudentDataTable extends StatelessWidget {
  final List students;
  final double threshold;
  const _StudentDataTable({required this.students, required this.threshold});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: AppColors.borderColor),
        child: DataTable(
          headingRowColor: MaterialStateProperty.all(AppColors.bgSecondary),
          columns: const [
            DataColumn(label: Text('Roll')),
            DataColumn(label: Text('Name')),
            DataColumn(label: Text('PRN')),
            DataColumn(label: Text('Sessions')),
            DataColumn(label: Text('Present')),
            DataColumn(label: Text('%')),
          ],
          rows: students.map((s) {
            final pct = (s['percentage'] as num).toDouble();
            final isAtRisk = pct < threshold;
            return DataRow(
              color: isAtRisk ? MaterialStateProperty.all(AppColors.danger.withOpacity(0.05)) : null,
              cells: [
                DataCell(Text(s['roll_number']?.toString() ?? '-')),
                DataCell(Text(s['student_name'])),
                DataCell(Text(s['prn'])),
                DataCell(Text(s['total_sessions'].toString())),
                DataCell(Text(s['present'].toString())),
                DataCell(Text('${pct.toStringAsFixed(1)}%', style: TextStyle(
                  color: isAtRisk ? AppColors.danger : AppColors.success,
                  fontWeight: FontWeight.bold,
                ))),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _SessionHistoryList extends ConsumerWidget {
  final String? allocationId;
  const _SessionHistoryList({this.allocationId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(teacherSessionHistoryProvider(allocationId));

    return historyAsync.when(
      loading: () => const LoadingWidget(),
      error: (e, _) => AppErrorWidget(
        message: e.toString(),
        onRetry: () => ref.invalidate(teacherSessionHistoryProvider(allocationId)),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyStateWidget(
            message: 'No past sessions',
            icon: Icons.history_rounded,
          );
        }
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: list.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final s = list[i];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${s['subject_name']} — Div ${s['division_name']}'),
              subtitle: Text('${s['date']} | ${s['start_time']} - ${s['end_time']}'),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${s['present_count']}/${s['total_students']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('${s['attendance_pct']}%', style: TextStyle(fontSize: 11, color: _pctColor(s['attendance_pct']))),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Color _pctColor(num pct) {
    if (pct >= 75) return AppColors.success;
    if (pct >= 60) return AppColors.warning;
    return AppColors.danger;
  }
}
