import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/layout/app_layout.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/api_client.dart';

class SuperAdminDashboardScreen extends ConsumerWidget {
  const SuperAdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AppLayout(
      title: 'Global Infrastructure',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Network Health',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 24),
            
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 600;
                final row1 = [
                  {'label': 'Active Institutions', 'value': '12', 'color': AppColors.primaryLight, 'icon': Icons.business_rounded},
                  {'label': 'Global Users', 'value': '15.4k', 'color': AppColors.accent, 'icon': Icons.people_alt_rounded},
                ];
                final row2 = [
                  {'label': 'System Uptime', 'value': '99.9%', 'color': AppColors.success, 'icon': Icons.offline_bolt_rounded},
                  {'label': 'Critical Logs', 'value': '4', 'color': AppColors.danger, 'icon': Icons.warning_amber_rounded},
                ];

                if (isWide) {
                  return Column(
                    children: [
                      Row(
                        children: row1.map((s) => Expanded(child: _buildStatTile(s, isDark))).toList(),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: row2.map((s) => Expanded(child: _buildStatTile(s, isDark))).toList(),
                      ),
                    ],
                  );
                } else {
                  return Column(
                    children: [
                      ...row1.map((s) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _buildStatTile(s, isDark),
                      )),
                      ...row2.map((s) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _buildStatTile(s, isDark),
                      )),
                    ],
                  );
                }
              },
            ),
            
            const SizedBox(height: 32),
            Text(
              'Institutional Management',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 16),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 3,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final colleges = ['Institute of Engineering', 'Science Academy', 'Medical College'];
                return Container(
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkCardBg : AppColors.cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark ? AppColors.darkBorderColor : AppColors.borderColor,
                      width: 1.2,
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.account_balance_rounded,
                        color: AppColors.primaryLight,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      colleges[i],
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'License: Active · Users: 1.2k',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    trailing: Icon(
                      Icons.settings_outlined,
                      color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                      size: 20,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatTile(Map<String, dynamic> s, bool isDark) {
    final Color color = s['color'] as Color;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.20), width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(s['icon'] as IconData, color: color, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s['label'].toString().toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  s['value'].toString(),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: color,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
