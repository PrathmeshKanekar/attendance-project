import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/layout/app_layout.dart';
import '../../core/layout/nav_config.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/empty_state_widget.dart';
import '../../core/widgets/error_widget.dart';
import '../../core/widgets/loading_widget.dart';

final usersListProvider =
    FutureProvider.family<Map<String, dynamic>, String>(
  (ref, paramsKey) async {
    // Parse the stable key back into params
    final parts = paramsKey.split('|');
    final params = {
      'role': parts[0],
      'is_approved': parts[1],
      'search': parts[2],
    };

    final api = ref.read(apiClientProvider);
    final res = await api.get('/api/auth/users/', params: params);
    
    // Ensure we handle the map correctly
    if (res.data is Map) {
      return Map<String, dynamic>.from(res.data);
    }
    return {'users': [], 'count': 0};
  },
);

class ManageUsersScreen extends ConsumerStatefulWidget {
  const ManageUsersScreen({super.key});

  @override
  ConsumerState<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

class _ManageUsersScreenState extends ConsumerState<ManageUsersScreen> {
  String _selectedRole = 'all';
  String _selectedStatus = 'all'; // all / approved / pending
  String _search = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Create a stable key for the family provider based on values, not identity
    final roleParam = _selectedRole == 'all' ? '' : _selectedRole;
    final statusParam = _selectedStatus == 'all'
        ? ''
        : (_selectedStatus == 'approved' ? 'true' : 'false');
    final searchParam = _search;
    
    final paramsKey = '$roleParam|$statusParam|$searchParam';

    final usersAsync = ref.watch(usersListProvider(paramsKey));

    return AppLayout(
      title: 'Manage Users',
      fab: FloatingActionButton.extended(
        onPressed: () => context.push('/admin/users/add'),
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Add User'),
        backgroundColor: AppColors.primaryLight,
      ),
      child: Column(
        children: [
          // ── Filter row ────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            color: AppColors.cardBg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterChip(
                        label: 'All Roles',
                        isSelected: _selectedRole == 'all',
                        onSelected: (v) => setState(() => _selectedRole = 'all'),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Teachers',
                        isSelected: _selectedRole == 'teacher',
                        onSelected: (v) => setState(() => _selectedRole = 'teacher'),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Students',
                        isSelected: _selectedRole == 'student',
                        onSelected: (v) => setState(() => _selectedRole = 'student'),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'HOD',
                        isSelected: _selectedRole == 'hod',
                        onSelected: (v) => setState(() => _selectedRole = 'hod'),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Lab Asst.',
                        isSelected: _selectedRole == 'lab_assistant',
                        onSelected: (v) => setState(() => _selectedRole = 'lab_assistant'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _FilterChip(
                      label: 'All Status',
                      isSelected: _selectedStatus == 'all',
                      onSelected: (v) => setState(() => _selectedStatus = 'all'),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Approved',
                      isSelected: _selectedStatus == 'approved',
                      onSelected: (v) => setState(() => _selectedStatus = 'approved'),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Pending',
                      isSelected: _selectedStatus == 'pending',
                      onSelected: (v) => setState(() => _selectedStatus = 'pending'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search by name or email...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _search.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _search = '');
                            },
                          )
                        : null,
                  ),
                  onSubmitted: (v) => setState(() => _search = v.trim()),
                ),
              ],
            ),
          ),

          // ── Users list ────────────────────────────────────
          Expanded(
            child: usersAsync.when(
              loading: () => const LoadingWidget(message: 'Searching users...'),
              error: (e, _) => AppErrorWidget(
                message: e.toString(),
                onRetry: () => ref.invalidate(usersListProvider(paramsKey)),
              ),
              data: (data) {
                final usersList = data['users'] as List? ?? [];
                final users = List<Map<String, dynamic>>.from(usersList);
                final count = data['count'] as int? ?? 0;

                if (users.isEmpty) {
                  return const EmptyStateWidget(
                    message: 'No users found',
                    icon: Icons.person_search_rounded,
                    subtitle: 'Try adjusting your filters or search query',
                  );
                }

                return Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      width: double.infinity,
                      color: AppColors.primaryLight.withOpacity(0.05),
                      child: Text(
                        'Showing $count users',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: users.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                        itemBuilder: (context, i) {
                          return _UserListTile(user: users[i]);
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final ValueChanged<bool> onSelected;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: onSelected,
      selectedColor: AppColors.primaryLight.withOpacity(0.2),
      checkmarkColor: AppColors.primaryLight,
      labelStyle: TextStyle(
        color: isSelected ? AppColors.primaryLight : AppColors.textSecondary,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      backgroundColor: AppColors.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? AppColors.primaryLight : AppColors.borderColor,
        ),
      ),
    );
  }
}

class _UserListTile extends StatelessWidget {
  final Map<String, dynamic> user;

  const _UserListTile({required this.user});

  @override
  Widget build(BuildContext context) {
    final role = user['role']?.toString() ?? '';
    final isApproved = user['is_approved'] == true;
    final fullName = user['full_name']?.toString() ?? 'Unknown';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: NavConfig.roleColor(role).withOpacity(0.12),
        child: Text(
          _initials(fullName),
          style: TextStyle(
            color: NavConfig.roleColor(role),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              fullName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          _RoleChip(role: role),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(user['email']?.toString() ?? '', style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 4),
          _StatusChip(isApproved: isApproved),
        ],
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
      onTap: () => context.push('/admin/users/${user['id']}'),
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

class _RoleChip extends StatelessWidget {
  final String role;
  const _RoleChip({required this.role});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: NavConfig.roleColor(role).withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        role.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(
          color: NavConfig.roleColor(role),
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final bool isApproved;
  const _StatusChip({required this.isApproved});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: (isApproved ? AppColors.success : AppColors.warning).withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isApproved ? 'APPROVED' : 'PENDING',
        style: TextStyle(
          color: isApproved ? AppColors.success : AppColors.warning,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
