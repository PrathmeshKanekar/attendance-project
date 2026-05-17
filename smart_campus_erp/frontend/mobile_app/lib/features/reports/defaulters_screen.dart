import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/layout/app_layout.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/error_widget.dart';
import '../../core/widgets/loading_widget.dart';
import '../../core/widgets/empty_state_widget.dart';
import '../teacher/providers/teacher_providers.dart';
import 'report_providers.dart';

class DefaultersScreen extends ConsumerStatefulWidget {
  const DefaultersScreen({super.key});

  @override
  ConsumerState<DefaultersScreen> createState() => _DefaultersScreenState();
}

class _DefaultersScreenState extends ConsumerState<DefaultersScreen> {
  String? _selectedAllocationId;
  double _threshold = 75.0;
  final _thresholdController = TextEditingController(text: '75');
  bool _isDownloading = false;

  @override
  void dispose() {
    _thresholdController.dispose();
    super.dispose();
  }

  Map<String, String> get _params => {
    if (_selectedAllocationId != null) 'allocation_id': _selectedAllocationId!,
    'threshold': _threshold.toString(),
  };

  Future<void> _downloadFile(String type) async {
    setState(() => _isDownloading = true);
    try {
      final api = ref.read(apiClientProvider);
      final endpoint = type == 'pdf' ? '/api/reports/download/pdf/' : '/api/reports/download/excel/';
      
      // If no allocation is selected, the defaulters view usually shows all,
      // but the download endpoint requires allocation_id.
      // We should either modify backend or inform user.
      if (_selectedAllocationId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a specific subject to download the report.')),
        );
        return;
      }

      final queryParams = {
        'allocation_id': _selectedAllocationId,
        'threshold'    : _threshold,
      };

      Directory? dir;
      if (Platform.isAndroid) {
        dir = Directory('/storage/emulated/0/Download');
        if (!await dir.exists()) dir = await getExternalStorageDirectory();
      } else {
        dir = await getApplicationDocumentsDirectory();
      }

      final extension = type == 'pdf' ? 'pdf' : 'xlsx';
      final fileName = 'defaulters_${DateTime.now().millisecondsSinceEpoch}.$extension';
      final savePath = '${dir!.path}/$fileName';

      await api.download(
        endpoint,
        savePath,
        queryParameters: queryParams,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Defaulters list (${type.toUpperCase()}) saved'),
            action: SnackBarAction(label: 'Open', onPressed: () => OpenFilex.open(savePath)),
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
    final defaultersAsync  = ref.watch(defaultersProvider(_params));

    return AppLayout(
      title: 'Defaulters List',
      actions: [
        if (_isDownloading)
          const Center(child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          ))
        else ...[
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () => _downloadFile('pdf'),
            tooltip: 'Download PDF',
          ),
          IconButton(
            icon: const Icon(Icons.table_view_outlined),
            onPressed: () => _downloadFile('excel'),
            tooltip: 'Download Excel',
          ),
        ]
      ],
      child: Column(
        children: [
          // ── Filter Section ──────────────────────────────
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: allocationsAsync.when(
                    data: (list) => DropdownButtonFormField<String>(
                      value: _selectedAllocationId,
                      decoration: const InputDecoration(
                        labelText: 'Subject',
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('All Subjects')),
                        ...list.map((a) => DropdownMenuItem(
                          value: a['id'].toString(),
                          child: Text(a['subject_name']),
                        )),
                      ],
                      onChanged: (val) => setState(() => _selectedAllocationId = val),
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (_, __) => const Text('Error'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _thresholdController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Threshold %',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.filled(
                  onPressed: () {
                    setState(() {
                      _threshold = double.tryParse(_thresholdController.text) ?? 75.0;
                    });
                    ref.invalidate(defaultersProvider(_params));
                  },
                  icon: const Icon(Icons.filter_list_rounded),
                ),
              ],
            ),
          ),

          // ── Summary Chips ──────────────────────────────
          defaultersAsync.when(
            data: (data) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _Chip(
                    label: 'Total Defaulters: ${data['count']}',
                    color: AppColors.danger,
                  ),
                  const SizedBox(width: 10),
                  _Chip(
                    label: 'Threshold: ${_threshold.toStringAsFixed(0)}%',
                    color: AppColors.primaryLight,
                  ),
                ],
              ),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),

          const SizedBox(height: 12),

          // ── Defaulters List ─────────────────────────────
          Expanded(
            child: defaultersAsync.when(
              loading: () => const LoadingWidget(),
              error: (e, _) => AppErrorWidget(
                message: e.toString(),
                onRetry: () => ref.invalidate(defaultersProvider(_params)),
              ),
              data: (data) {
                final list = data['defaulters'] as List;
                if (list.isEmpty) {
                  return const EmptyStateWidget(
                    message: 'No defaulters found!',
                    subtitle: 'All students are above the threshold ✓',
                    icon: Icons.check_circle_outline_rounded,
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final s = list[i];
                    final pct = (s['percentage'] as num).toDouble();
                    return _DefaulterCard(student: s, pct: pct);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _DefaulterCard extends StatelessWidget {
  final Map<String, dynamic> student;
  final double pct;
  const _DefaulterCard({required this.student, required this.pct});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: const Border(
          left: BorderSide(color: AppColors.danger, width: 4),
          top: BorderSide(color: AppColors.borderColor),
          right: BorderSide(color: AppColors.borderColor),
          bottom: BorderSide(color: AppColors.borderColor),
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
                      student['student_name'],
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    Text(
                      'PRN: ${student['prn']}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.danger.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${pct.toStringAsFixed(1)}%',
                  style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (student['subject_name'] != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Subject: ${student['subject_name']}',
                style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
              ),
            ),
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.warning),
              const SizedBox(width: 4),
              Text(
                '${student['absent']} classes missed out of ${student['total_sessions']}',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct / 100,
              backgroundColor: AppColors.bgSecondary,
              color: AppColors.danger,
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }
}
