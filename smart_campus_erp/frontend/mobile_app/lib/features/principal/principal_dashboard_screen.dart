import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/layout/app_layout.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/network/api_client.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/stat_card.dart';
import '../../core/widgets/loading_widget.dart';
import '../../core/widgets/error_widget.dart';
import '../../core/widgets/empty_state_widget.dart';

final pendingApprovalsProvider = FutureProvider<List>((ref) async {
  final api = ref.read(apiClientProvider);
  final res = await api.get('/api/auth/users/', params: {'is_approved': 'false'});
  final list = res.data['users'] as List? ?? [];
  return list;
});

final collegeStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final api = ref.read(apiClientProvider);
  final res = await api.get('/api/auth/users/');
  final users = res.data['users'] as List? ?? [];
  return {
    'total_users' : users.length,
    'pending'     : users.where((u) => u['is_approved'] == false).length,
    'teachers'    : users.where((u) => u['role'] == 'teacher').length,
    'students'    : users.where((u) => u['role'] == 'student').length,
  };
});

class PrincipalDashboardScreen extends ConsumerWidget {
  const PrincipalDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    if (authState is! AuthSuccess) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final user = authState.user;
    final statsAsync = ref.watch(collegeStatsProvider);
    final pendingAsync = ref.watch(pendingApprovalsProvider);

    return AppLayout(
      title: 'Principal Dashboard',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // SECTION 1 — Greeting
            Text(
              'Good morning, ${user.firstName}! 👋',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${user.collegeName ?? ""}  ·  College Administrator Mode',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 24),

            // SECTION 2 — Stat cards
            statsAsync.when(
              loading: () => const LoadingWidget(message: 'Loading stats...'),
              error: (e, _) => AppErrorWidget(
                message: e.toString(),
                onRetry: () => ref.invalidate(collegeStatsProvider),
              ),
              data: (stats) => GridView.count(
                crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.2,
                children: [
                  StatCard(
                    label: 'Total Users',
                    value: '${stats['total_users']}',
                    icon: Icons.people_rounded,
                    accentColor: AppColors.primaryLight,
                    subtitle: 'All users in college',
                  ),
                  StatCard(
                    label: 'Pending Approvals',
                    value: '${stats['pending']}',
                    icon: Icons.pending_actions_rounded,
                    accentColor: AppColors.warning,
                    subtitle: 'Action required',
                  ),
                  StatCard(
                    label: 'Teachers',
                    value: '${stats['teachers']}',
                    icon: Icons.person_rounded,
                    accentColor: AppColors.success,
                    subtitle: 'Active faculty members',
                  ),
                  StatCard(
                    label: 'Students',
                    value: '${stats['students']}',
                    icon: Icons.school_rounded,
                    accentColor: AppColors.accent,
                    subtitle: 'Enrolled students',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // SECTION 3 — Pending Approvals list
            Row(
              children: [
                const Text(
                  'Pending Approvals',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                pendingAsync.maybeWhen(
                  data: (users) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${users.length}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                  orElse: () => const SizedBox.shrink(),
                ),
              ],
            ),
            const SizedBox(height: 12),

            pendingAsync.when(
              loading: () => const LoadingWidget(),
              error: (e, _) => AppErrorWidget(
                message: e.toString(),
                onRetry: () => ref.invalidate(pendingApprovalsProvider),
              ),
              data: (users) {
                if (users.isEmpty) {
                  return const EmptyStateWidget(
                    message: 'No pending approvals',
                    icon: Icons.check_circle_outline_rounded,
                    subtitle: 'Great job! All users are currently approved',
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: users.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final u = users[i] as Map<String, dynamic>;
                    return _ApprovalCard(user: u);
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ApprovalCard extends ConsumerWidget {
  final Map<String, dynamic> user;
  const _ApprovalCard({required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user['full_name']?.toString() ?? 'Unknown User',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user['email']?.toString() ?? '',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  user['role']?.toString().toUpperCase() ?? '',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppColors.accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: () => _handleReject(context, ref),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: const BorderSide(color: AppColors.danger),
                ),
                child: const Text('Reject'),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: () => _handleApprove(context, ref),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Approve'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _handleApprove(BuildContext context, WidgetRef ref) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.post('/api/auth/users/${user['id']}/approve/');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User approved successfully!')),
        );
      }
      ref.invalidate(pendingApprovalsProvider);
      ref.invalidate(collegeStatsProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error approving user: $e')),
        );
      }
    }
  }

  void _handleReject(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Reason'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Enter reason here...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                final api = ref.read(apiClientProvider);
                await api.post('/api/auth/users/${user['id']}/reject/', data: {
                  'reason': controller.text.trim(),
                });
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('User rejected successfully!')),
                  );
                }
                ref.invalidate(pendingApprovalsProvider);
                ref.invalidate(collegeStatsProvider);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error rejecting user: $e')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }
}
