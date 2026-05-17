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
    return AppLayout(
      title: 'Lab Assistant Dashboard',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Laboratory Operations',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 24),
            
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.5,
              children: [
                StatCard(
                  label: 'Assigned Labs',
                  value: '3',
                  icon: Icons.biotech_rounded,
                  accentColor: AppColors.primaryLight,
                ),
                StatCard(
                  label: 'Pending Calibrations',
                  value: '1',
                  icon: Icons.compass_calibration_rounded,
                  accentColor: AppColors.warning,
                ),
              ],
            ),
            
            const SizedBox(height: 32),
            const Text(
              'Spatial Management',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 12),
            _buildActionCard(
              context,
              title: 'Virtual Room Capture',
              subtitle: 'Walk and mark boundaries for new labs/classrooms.',
              icon: Icons.layers_outlined,
              color: AppColors.success,
              onTap: () => context.push('/virtual-rooms'),
            ),
            const SizedBox(height: 16),
            _buildActionCard(
              context,
              title: 'Location Audits',
              subtitle: 'Verify signal strength and GPS accuracy in labs.',
              icon: Icons.track_changes_rounded,
              color: AppColors.accent,
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard(BuildContext context, {required String title, required String subtitle, required IconData icon, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
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
              decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
