import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/layout/app_layout.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/api_client.dart';

class UserManagementScreen extends ConsumerWidget {
  const UserManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppLayout(
      title: 'User Management',
      child: DefaultTabController(
        length: 3,
        child: Column(
          children: [
            const TabBar(
              labelColor: AppColors.primaryLight,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primaryLight,
              tabs: [
                Tab(text: 'Teachers'),
                Tab(text: 'Students'),
                Tab(text: 'Staff'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _UserList(role: 'teacher'),
                  _UserList(role: 'student'),
                  _UserList(role: 'lab_assistant'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final usersByRoleProvider = FutureProvider.family<List, String>((ref, role) async {
  final api = ref.read(apiClientProvider);
  final res = await api.get('/api/auth/users/', params: {'role': role});
  return (res.data['results'] ?? res.data['users'] ?? []) as List;
});

class _UserList extends ConsumerWidget {
  final String role;
  const _UserList({required this.role});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(usersByRoleProvider(role));

    return usersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (users) => ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: users.length,
        separatorBuilder: (_, __) => const Divider(),
        itemBuilder: (context, i) {
          final u = users[i];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.primary.withOpacity(0.1),
              child: const Icon(Icons.person, color: AppColors.primary),
            ),
            title: Text('${u['first_name']} ${u['last_name']}'),
            subtitle: Text(u['email']),
            trailing: Chip(
              label: Text(u['is_active'] ? 'Active' : 'Inactive', style: const TextStyle(fontSize: 10)),
              backgroundColor: u['is_active'] ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
            ),
          );
        },
      ),
    );
  }
}
