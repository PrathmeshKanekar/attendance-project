import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/layout/app_layout.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/empty_state_widget.dart';
import '../../core/widgets/error_widget.dart';
import '../../core/widgets/loading_widget.dart';

// ── Provider ────────────────────────────────────────────────
final pendingApprovalsProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final api = ref.read(apiClientProvider);

  // Fetch Staff Approvals
  final staffRes = await api.get('/api/auth/users/pending/');
  final staffData = Map<String, dynamic>.from(staffRes.data as Map);
  final staffList =
      List<Map<String, dynamic>>.from(staffData['pending_users'] as List);

  // Fetch Student Registrations (New)
  try {
    final studentRes = await api.get('/api/students/approvals/');
    final studentList =
        List<Map<String, dynamic>>.from(studentRes.data as List);

    // Transform students to match staff format for the UI
    final mappedStudents = studentList
        .map((s) => {
              'id': s['id'],
              'full_name': s['name'],
              'email': s['email'],
              'role': 'student',
              'days_waiting': 0, // Placeholder
              'is_student_reg': true, // Flag for specific action
              'prn': s['prn'],
              'division': s['division'],
              'face_image_url': s['face_image_url'],
            })
        .toList();

    return {
      'pending_users': [...staffList, ...mappedStudents],
      'count': staffList.length + mappedStudents.length,
    };
  } catch (e) {
    return {
      'pending_users': staffList,
      'count': staffList.length,
    };
  }
});

class ApprovalsScreen extends ConsumerWidget {
  const ApprovalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pendingApprovalsProvider);

    return AppLayout(
      title: 'Pending Approvals',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: () => ref.invalidate(pendingApprovalsProvider),
        ),
      ],
      child: async.when(
        loading: () => const LoadingWidget(message: 'Loading approvals...'),
        error: (e, _) {
          if (e is DioException && e.response?.statusCode == 403) {
            return const Center(
              child: Text(
                'Permission denied: Only Principal can manage approvals.',
                style: TextStyle(color: AppColors.danger),
              ),
            );
          }
          return AppErrorWidget(
            message: e.toString(),
            onRetry: () => ref.invalidate(pendingApprovalsProvider),
          );
        },
        data: (data) {
          final users = List<Map<String, dynamic>>.from(
            data['pending_users'] as List,
          );
          final count = data['count'] as int? ?? 0;

          if (users.isEmpty) {
            return const EmptyStateWidget(
              message: 'No pending approvals',
              icon: Icons.check_circle_rounded,
              subtitle: 'All users have been reviewed',
            );
          }

          return Column(
            children: [
              // Count banner
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                color: AppColors.warning.withOpacity(0.08),
                child: Row(
                  children: [
                    const Icon(
                      Icons.pending_actions_rounded,
                      color: AppColors.warning,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '$count user${count == 1 ? '' : 's'} '
                      'awaiting approval',
                      style: const TextStyle(
                        color: AppColors.warning,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: users.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    return _ApprovalCard(
                      user: users[i],
                      onApprove: () => _approve(context, ref, users[i]),
                      onReject: () => _rejectDialog(context, ref, users[i]),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _approve(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> user,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve User'),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        content: Text(
          'Approve ${user['full_name']} as '
          '${_roleLabel(user['role'].toString())}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      final isStudent = user['is_student_reg'] == true;
      final endpoint = isStudent
          ? '/api/students/approvals/${user['id']}/'
          : '/api/auth/users/${user['id']}/approve/';

      await ref.read(apiClientProvider).post(
            endpoint,
            data: isStudent ? {'action': 'approve'} : null,
          );
      ref.invalidate(pendingApprovalsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${user['full_name']} approved.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 403 && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You do not have permission to perform this action.'),
            backgroundColor: AppColors.danger,
          ),
        );
        return;
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _rejectDialog(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> user,
  ) async {
    final reasonCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject User'),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Rejecting ${user['full_name']}. '
                'Please provide a reason:',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: reasonCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Enter rejection reason...',
                  labelText: 'Reason',
                ),
                validator: (v) => (v == null || v.trim().length < 5)
                    ? 'Reason must be at least 5 characters'
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
            ),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      final isStudent = user['is_student_reg'] == true;
      final endpoint = isStudent
          ? '/api/students/approvals/${user['id']}/'
          : '/api/auth/users/${user['id']}/reject/';

      await ref.read(apiClientProvider).post(
        endpoint,
        data: {
          'reason': reasonCtrl.text.trim(),
          if (isStudent) 'action': 'reject'
        },
      );
      ref.invalidate(pendingApprovalsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${user['full_name']} rejected.'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 403 && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You do not have permission to perform this action.'),
            backgroundColor: AppColors.danger,
          ),
        );
        return;
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  String _roleLabel(String role) => role.replaceAll('_', ' ').toUpperCase();
}

// ── Approval card widget ───────────────────────────────────
class _ApprovalCard extends StatelessWidget {
  final Map<String, dynamic> user;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _ApprovalCard({
    required this.user,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final role = user['role']?.toString() ?? '';
    final daysWaiting = user['days_waiting'] as int? ?? 0;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left Warning Bar
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: AppColors.warning,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
              ),
            ),
            // Card Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header ────────────────────────────────────
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Face Image or Initials
                        Container(
                          width: 70,
                          height: 70,
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.borderColor),
                          ),
                          child: user['face_image_url'] != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(11),
                                  child: Image.network(
                                    user['face_image_url'],
                                    fit: BoxFit.cover,
                                    errorBuilder: (c, e, s) => Center(
                                      child: Text(
                                        _initials(
                                            user['full_name']?.toString() ??
                                                ''),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                )
                              : Center(
                                  child: Text(
                                    _initials(
                                        user['full_name']?.toString() ?? ''),
                                    style: const TextStyle(
                                      color: AppColors.primaryLight,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user['full_name']?.toString() ?? '',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 17,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                user['email']?.toString() ?? '',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (user['is_student_reg'] == true) ...[
                                Row(
                                  children: [
                                    const Icon(Icons.badge_outlined,
                                        size: 14,
                                        color: AppColors.primaryLight),
                                    const SizedBox(width: 4),
                                    Text(
                                      'PRN: ${user['prn'] ?? 'N/A'}',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.groups_outlined,
                                        size: 14,
                                        color: AppColors.primaryLight),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Division: ${user['division'] ?? 'N/A'}',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        // Days waiting badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: daysWaiting > 2
                                ? AppColors.danger.withOpacity(0.10)
                                : AppColors.warning.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            daysWaiting == 0
                                ? 'Today'
                                : '$daysWaiting day${daysWaiting == 1 ? '' : 's'}',
                            style: TextStyle(
                              color: daysWaiting > 2
                                  ? AppColors.danger
                                  : AppColors.warning,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // ── Info chips ────────────────────────────────
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _InfoChip(
                          label: role.replaceAll('_', ' ').toUpperCase(),
                          color: AppColors.primaryLight,
                        ),
                        if (user['phone'] != null && user['phone'] != '')
                          _InfoChip(
                            label: user['phone'].toString(),
                            color: AppColors.textSecondary,
                          ),
                        if (user['is_student_reg'] == true)
                          const _InfoChip(
                            label: 'STUDENT REGISTRATION',
                            color: AppColors.success,
                          ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // ── Action buttons ────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.danger,
                              side: const BorderSide(color: AppColors.danger),
                              minimumSize: const Size(0, 44),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: onReject,
                            icon: const Icon(Icons.close_rounded, size: 18),
                            label: const Text('Reject'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                              minimumSize: const Size(0, 44),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: onApprove,
                            icon: const Icon(Icons.check_rounded, size: 18),
                            label: const Text('Approve'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final Color color;
  const _InfoChip({required this.label, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
