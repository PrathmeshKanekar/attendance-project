import 'package:flutter/material.dart';
import '../../core/layout/app_layout.dart';
import '../../core/theme/app_theme.dart';

class ManageUsersScreen extends StatelessWidget {
  const ManageUsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title: 'Users',
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Manage System Users'),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'User Accounts Management',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'View, activate, and modify user login accounts.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              Card(
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: 4,
                  separatorBuilder: (context, index) => const Divider(),
                  itemBuilder: (context, index) {
                    final users = [
                      {'name': 'Arvind Kumar', 'role': 'Teacher', 'status': 'Active', 'color': AppColors.success},
                      {'name': 'Shyam Lal', 'role': 'Lab Assistant', 'status': 'Active', 'color': AppColors.success},
                      {'name': 'Rajesh Sharma', 'role': 'HOD', 'status': 'Active', 'color': AppColors.success},
                      {'name': 'Amit Patil', 'role': 'Student', 'status': 'Pending Approval', 'color': AppColors.warning},
                    ];
                    final u = users[index];
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(u['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('Role: ${u['role']}'),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: (u['color'] as Color).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          u['status'] as String,
                          style: TextStyle(color: u['color'] as Color, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
