import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/layout/app_layout.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/empty_state_widget.dart';
import '../../core/widgets/error_widget.dart';
import '../../core/widgets/loading_widget.dart';
import 'providers/teacher_providers.dart';

class SessionLogsScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> session;
  const SessionLogsScreen({super.key, required this.session});

  @override
  ConsumerState<SessionLogsScreen> createState() => _SessionLogsScreenState();
}

class _SessionLogsScreenState extends ConsumerState<SessionLogsScreen> {
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.session.isEmpty || widget.session['id'] == null) {
      return const AppLayout(
        title: 'Session Logs',
        child: Center(child: Text('Session not found.')),
      );
    }


    final sessionId = widget.session['id'].toString();
    final logsAsync = ref.watch(sessionLogsProvider(sessionId));

    return AppLayout(
      title: 'Session Attendance Logs',
      child: RefreshIndicator(
        onRefresh: () async => ref.refresh(sessionLogsProvider(sessionId)),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              logsAsync.when(
                loading: () => const LoadingWidget(),
                error: (e, _) => AppErrorWidget(
                  message: e.toString(),
                  onRetry: () => ref.refresh(sessionLogsProvider(sessionId)),
                ),
                data: (data) {
                  final sessionData = data['session'] as Map<String, dynamic>? ?? {};
                  final logs        = data['logs'] as List? ?? [];

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Overview card
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.cardBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.borderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sessionData['subject_name'] ?? 'Subject Logs',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Code: ${sessionData['session_code'] ?? "N/A"} · Div ${sessionData['division_name'] ?? "N/A"}',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _statRow('Present', '${data['present_count']}', AppColors.success),
                                _statRow('Absent', '${data['absent_count']}', AppColors.danger),
                                _statRow('Manual', '${data['manual_count']}', AppColors.primaryLight),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Attendance list
                      const Text(
                        'Student Status List',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),

                      if (logs.isEmpty)
                        const EmptyStateWidget(
                          message: 'No logs recorded yet',
                          icon: Icons.assignment_rounded,
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: logs.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, idx) {
                            final log = logs[idx];
                            final status = log['status']?.toString().toLowerCase();

                            Color badgeColor;
                            if (status == 'present') {
                              badgeColor = AppColors.success;
                            } else if (status == 'absent') {
                              badgeColor = AppColors.danger;
                            } else {
                              badgeColor = AppColors.primaryLight;
                            }

                            return Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.cardBg,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.borderColor),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          log['student_name'] ?? 'Unknown Student',
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'PRN: ${log['student_prn'] ?? "N/A"}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                        if (log['is_verified_gps'] == true ||
                                            log['is_verified_face'] == true)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Text(
                                              'GPS: ${log['is_verified_gps']}  ·  Face: ${log['is_verified_face']}',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.teal,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        if (log['manual_reason'] != null)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Text(
                                              'Reason: ${log['manual_reason']}',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey,
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: badgeColor.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          status?.toUpperCase() ?? 'N/A',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: badgeColor,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      if (status != 'present' && status != 'manual')
                                        IconButton(
                                          onPressed: () => _markManual(log['student'], sessionId),
                                          icon: const Icon(
                                            Icons.edit_note_rounded,
                                            color: AppColors.primaryLight,
                                          ),
                                          tooltip: 'Mark Present Manually',
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statRow(String lbl, String val, Color c) {
    return Column(
      children: [
        Text(
          val,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: c,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          lbl,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Future<void> _markManual(String studentId, String sessionId) async {
    _reasonController.clear();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark Manually Present'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter the override reason or justification for manual marking.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason',
                hintText: 'Medical leave, approved absence, etc.',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryLight,
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed == true && _reasonController.text.trim().isNotEmpty) {
      try {
        final api = ref.read(apiClientProvider);
        await api.post('/api/attendance/manual/', data: {
          'session_id': sessionId,
          'student_id': studentId,
          'reason'    : _reasonController.text.trim(),
        });
        ref.invalidate(sessionLogsProvider(sessionId));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Attendance marked manually.'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e'),
              backgroundColor: AppColors.danger,
            ),
          );
        }
      }
    }
  }
}
