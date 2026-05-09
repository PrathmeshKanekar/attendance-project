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

final platformStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final api = ref.read(apiClientProvider);
  try {
    final res = await api.get('/api/colleges/');
    final colleges = res.data is List ? res.data : [];
    return {
      'total_colleges': colleges.length,
      'active_colleges': colleges.where((c) => c['is_active'] == true).length,
    };
  } catch (_) {
    return {
      'total_colleges': 0,
      'active_colleges': 0,
    };
  }
});

final collegesListProvider = FutureProvider<List>((ref) async {
  final api = ref.read(apiClientProvider);
  try {
    final res = await api.get('/api/colleges/');
    return res.data is List ? res.data : [];
  } catch (_) {
    return [];
  }
});

class SuperAdminDashboardScreen extends ConsumerWidget {
  const SuperAdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    if (authState is! AuthSuccess) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final user = authState.user;
    final statsAsync = ref.watch(platformStatsProvider);
    final collegesAsync = ref.watch(collegesListProvider);

    return AppLayout(
      title: 'Super Admin',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // SECTION 1 — Platform Overview
            Text(
              'Good morning, ${user.firstName}! 👋',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Super Admin Platform Overview Mode',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 24),

            statsAsync.when(
              loading: () => const LoadingWidget(message: 'Loading stats...'),
              error: (e, _) => AppErrorWidget(
                message: e.toString(),
                onRetry: () => ref.invalidate(platformStatsProvider),
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
                    label: 'Total Colleges',
                    value: '${stats['total_colleges']}',
                    icon: Icons.school_rounded,
                    accentColor: AppColors.primaryLight,
                    subtitle: 'Registered institutions',
                  ),
                  StatCard(
                    label: 'Active Colleges',
                    value: '${stats['active_colleges']}',
                    icon: Icons.check_circle_rounded,
                    accentColor: AppColors.success,
                    subtitle: 'Currently operational',
                  ),
                  const StatCard(
                    label: 'All Users',
                    value: '0',
                    icon: Icons.people_rounded,
                    accentColor: AppColors.accent,
                    subtitle: 'Platform-wide users',
                  ),
                  const StatCard(
                    label: 'Platform Status',
                    value: 'Active',
                    icon: Icons.cloud_done_rounded,
                    accentColor: AppColors.success,
                    subtitle: 'System operational',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // SECTION 2 — Colleges list
            const Text(
              'Colleges',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),

            collegesAsync.when(
              loading: () => const LoadingWidget(),
              error: (e, _) => AppErrorWidget(
                message: e.toString(),
                onRetry: () => ref.invalidate(collegesListProvider),
              ),
              data: (colleges) {
                if (colleges.isEmpty) {
                  return const EmptyStateWidget(
                    message: 'No colleges onboarded yet',
                    icon: Icons.school_rounded,
                    subtitle: 'Create a new college using super admin controls',
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: colleges.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final c = colleges[i] as Map<String, dynamic>;
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.cardBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.borderColor),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c['name']?.toString() ?? 'College Name',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Code: ${c['code'] ?? ""}  ·  Domain: ${c['email_domain'] ?? ""}',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: (c['is_active'] == true)
                                  ? AppColors.success.withOpacity(0.12)
                                  : AppColors.danger.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              (c['is_active'] == true) ? 'Active' : 'Inactive',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: (c['is_active'] == true)
                                    ? AppColors.success
                                    : AppColors.danger,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
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
