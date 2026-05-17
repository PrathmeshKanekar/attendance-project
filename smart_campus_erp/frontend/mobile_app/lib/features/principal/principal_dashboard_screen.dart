import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/layout/app_layout.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/network/api_client.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/stat_card.dart';
import '../../core/widgets/loading_widget.dart';
import '../../core/widgets/error_widget.dart';
import '../../core/widgets/empty_state_widget.dart';

final collegeStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final api = ref.read(apiClientProvider);
  final usersRes = await api.get('/api/auth/users/');
  final pendingRes = await api.get('/api/approvals/pending/');
  
  final users   = usersRes.data['users'] as List? ?? [];
  final pending = pendingRes.data['count'] as int? ?? 0;
  
  return {
    'total_users' : users.length,
    'teachers'    : users.where((u) => u['role'] == 'teacher').length,
    'pending'     : pending,
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

    return AppLayout(
      title: 'Executive Dashboard',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // SECTION 1 — Greeting
            Text(
              'Welcome back, ${user.firstName}! 👋',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${user.collegeName ?? ""}  ·  Chief Institutional Authority',
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
                    label: 'Pending Approvals',
                    value: '${stats['pending']}',
                    icon: Icons.pending_actions_rounded,
                    accentColor: AppColors.warning,
                    subtitle: 'Requires action',
                  ),
                  StatCard(
                    label: 'Active Faculty',
                    value: '${stats['teachers']}',
                    icon: Icons.people_rounded,
                    accentColor: AppColors.primaryLight,
                    subtitle: 'Teaching staff',
                  ),
                  StatCard(
                    label: 'Total Campus',
                    value: '${stats['total_users']}',
                    icon: Icons.school_rounded,
                    accentColor: AppColors.accent,
                    subtitle: 'All residents',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // SECTION 3 — Quick Actions
            const Text(
              'Personnel Management',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.borderColor),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.verified_user_rounded, color: AppColors.warning),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pending Staff Approvals',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        Text(
                          'Review and authorize new teachers and lab assistants.',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ElevatedButton(
                      onPressed: () => context.push('/principal/approvals'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.warning,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Review'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // SECTION 4 — Overview
            const Text(
              'Institutional Overview',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.borderColor),
              ),
              child: const Column(
                children: [
                  Icon(Icons.analytics_outlined, size: 48, color: AppColors.textSecondary),
                  SizedBox(height: 16),
                  Text(
                    'Academic Reporting',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Use the side menu to view detailed attendance reports, defaulter lists, and institutional analytics.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
