import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/layout/app_layout.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/stat_card.dart';

class LabDashboardScreen extends ConsumerWidget {
  const LabDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AppLayout(
      title: 'Lab Assistant Dashboard',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Laboratory Operations',
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
                return isWide
                    ? Row(
                        children: [
                          Expanded(
                            child: StatCard(
                              label: 'Assigned Labs',
                              value: '3',
                              icon: Icons.biotech_rounded,
                              accentColor: AppColors.primaryLight,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: StatCard(
                              label: 'Pending Calibrations',
                              value: '1',
                              icon: Icons.compass_calibration_rounded,
                              accentColor: AppColors.warning,
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          StatCard(
                            label: 'Assigned Labs',
                            value: '3',
                            icon: Icons.biotech_rounded,
                            accentColor: AppColors.primaryLight,
                          ),
                          const SizedBox(height: 16),
                          StatCard(
                            label: 'Pending Calibrations',
                            value: '1',
                            icon: Icons.compass_calibration_rounded,
                            accentColor: AppColors.warning,
                          ),
                        ],
                      );
              },
            ),
            
            const SizedBox(height: 36),
            Text(
              'Spatial Management',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 16),
            _buildActionCard(
              context,
              title: 'Virtual Room Capture',
              subtitle: 'Walk and mark boundaries for new labs/classrooms.',
              icon: Icons.layers_outlined,
              color: AppColors.success,
              isDark: isDark,
              onTap: () => context.push('/virtual-rooms'),
            ),
            const SizedBox(height: 16),
            _buildActionCard(
              context,
              title: 'Location Audits',
              subtitle: 'Verify signal strength and GPS accuracy in labs.',
              icon: Icons.track_changes_rounded,
              color: AppColors.accent,
              isDark: isDark,
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCardBg : AppColors.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? AppColors.darkBorderColor : AppColors.borderColor,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          hoverColor: color.withOpacity(0.04),
          splashColor: color.withOpacity(0.08),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
