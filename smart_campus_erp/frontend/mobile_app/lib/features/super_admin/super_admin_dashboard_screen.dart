import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/layout/app_layout.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/api_client.dart';

class SuperAdminDashboardScreen extends ConsumerWidget {
  const SuperAdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppLayout(
      title: 'Global Infrastructure',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Network Health',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 24),
            
            _buildStatRow([
              {'label': 'Active Institutions', 'value': '12', 'color': AppColors.primaryLight},
              {'label': 'Global Users', 'value': '15.4k', 'color': AppColors.accent},
            ]),
            const SizedBox(height: 16),
            _buildStatRow([
              {'label': 'System Uptime', 'value': '99.9%', 'color': AppColors.success},
              {'label': 'Critical Logs', 'value': '4', 'color': AppColors.danger},
            ]),
            
            const SizedBox(height: 32),
            const Text(
              'Institutional Management',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 12),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 3,
              itemBuilder: (context, i) {
                final colleges = ['Institute of Engineering', 'Science Academy', 'Medical College'];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.account_balance_rounded, color: AppColors.primary),
                    title: Text(colleges[i]),
                    subtitle: const Text('License: Active · Users: 1.2k'),
                    trailing: const Icon(Icons.settings_outlined),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(List stats) {
    return Row(
      children: stats.map((s) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: s['color'].withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: s['color'].withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s['label'], style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              Text(s['value'], style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: s['color'])),
            ],
          ),
        ),
      )).toList(),
    );
  }
}
