import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_colors.dart';
import '../../core/layout/app_layout.dart';
import '../../core/layout/nav_config.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/error_widget.dart';
import '../../core/widgets/loading_widget.dart';

final userDetailProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, userId) async {
  final api = ref.read(apiClientProvider);
  final res = await api.get('/api/auth/users/$userId/');
  return Map<String, dynamic>.from(res.data as Map);
});

class UserDetailScreen extends ConsumerStatefulWidget {
  final String userId;
  const UserDetailScreen({super.key, required this.userId});

  @override
  ConsumerState<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends ConsumerState<UserDetailScreen> {
  bool _isProcessing = false;

  Future<void> _approve() async {
    final confirmed = await _showConfirm('Approve User', 'Are you sure you want to approve this user?');
    if (!confirmed) return;

    setState(() => _isProcessing = true);
    try {
      await ref.read(apiClientProvider).post('/api/auth/users/${widget.userId}/approve/');
      ref.invalidate(userDetailProvider(widget.userId));
      if (mounted) _showSnack('User approved successfully.', AppColors.success);
    } catch (e) {
      if (mounted) _showSnack(e.toString(), AppColors.danger);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _reject() async {
    final reasonCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject User'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: reasonCtrl,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Rejection Reason', hintText: 'Enter reason...'),
            validator: (v) => (v == null || v.trim().length < 5) ? 'Reason too short' : null,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isProcessing = true);
    try {
      await ref.read(apiClientProvider).post(
            '/api/auth/users/${widget.userId}/reject/',
            data: {'reason': reasonCtrl.text.trim()},
          );
      ref.invalidate(userDetailProvider(widget.userId));
      if (mounted) _showSnack('User rejected.', AppColors.warning);
    } catch (e) {
      if (mounted) _showSnack(e.toString(), AppColors.danger);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _deactivate() async {
    final confirmed = await _showConfirm('Deactivate User', 'This user will no longer be able to log in. Proceed?');
    if (!confirmed) return;

    setState(() => _isProcessing = true);
    try {
      await ref.read(apiClientProvider).post('/api/auth/users/${widget.userId}/deactivate/');
      ref.invalidate(userDetailProvider(widget.userId));
      if (mounted) _showSnack('User account deactivated.', AppColors.warning);
    } catch (e) {
      if (mounted) _showSnack(e.toString(), AppColors.danger);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<bool> _showConfirm(String title, String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
            ],
          ),
        ) ??
        false;
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(userDetailProvider(widget.userId));

    return AppLayout(
      title: 'User Details',
      child: userAsync.when(
        loading: () => const LoadingWidget(),
        error: (e, _) => AppErrorWidget(
          message: e.toString(),
          onRetry: () => ref.invalidate(userDetailProvider(widget.userId)),
        ),
        data: (user) {
          final fullName = user['full_name']?.toString() ?? '';
          final role = user['role']?.toString() ?? '';
          final isApproved = user['is_approved'] == true;
          final isActive = user['is_active'] == true;
          final student = user['student'] as Map<String, dynamic>?;

          return Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // ── Profile Header ──────────────────────────
                    _Card(
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 32,
                            backgroundColor: NavConfig.roleColor(role).withOpacity(0.1),
                            child: Text(
                              fullName.isNotEmpty ? fullName[0].toUpperCase() : '?',
                              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: NavConfig.roleColor(role)),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(fullName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                _RoleChip(role: role),
                                const SizedBox(height: 4),
                                Text(user['email']?.toString() ?? '', style: const TextStyle(color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Status Chips ────────────────────────────
                    Row(
                      children: [
                        _StatusChip(
                          label: isApproved ? 'Approved' : 'Pending',
                          icon: isApproved ? Icons.check_circle_outline : Icons.hourglass_empty,
                          color: isApproved ? AppColors.success : AppColors.warning,
                        ),
                        const SizedBox(width: 8),
                        _StatusChip(
                          label: isActive ? 'Active' : 'Inactive',
                          icon: Icons.power_settings_new,
                          color: isActive ? AppColors.success : AppColors.danger,
                        ),
                        if (student != null) ...[
                          const SizedBox(width: 8),
                          _StatusChip(
                            label: student['face_registered'] == true ? 'Face Registered' : 'No Face',
                            icon: Icons.face_retouching_natural,
                            color: student['face_registered'] == true ? AppColors.success : AppColors.warning,
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: 16),

                    // ── Details Card ────────────────────────────
                    _Card(
                      child: Column(
                        children: [
                          _DetailTile(label: 'Email', value: user['email']),
                          _DetailTile(label: 'Phone', value: user['phone'] ?? 'Not provided'),
                          _DetailTile(label: 'College', value: user['college_name']),
                          _DetailTile(label: 'Last Login', value: _formatDate(user['last_login_at'])),
                          _DetailTile(label: 'Joined', value: _formatDate(user['created_at'])),
                          _DetailTile(label: 'Approved By', value: user['approved_by'] ?? 'System'),
                          if (student != null) ...[
                            const Divider(),
                            _DetailTile(label: 'PRN', value: student['prn']),
                            _DetailTile(label: 'Roll No', value: student['roll_number']),
                            _DetailTile(label: 'Year', value: 'Year ${student['year_of_study']}'),
                            _DetailTile(label: 'Division', value: student['division_name']),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // ── Actions ─────────────────────────────────
                    if (!isApproved) ...[
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _isProcessing ? null : _approve,
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('Approve User'),
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: _isProcessing ? null : _reject,
                          icon: const Icon(Icons.close_rounded),
                          label: const Text('Reject Registration'),
                          style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger, side: const BorderSide(color: AppColors.danger)),
                        ),
                      ),
                    ],

                    if (isApproved && isActive) ...[
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: _isProcessing ? null : _deactivate,
                          icon: const Icon(Icons.no_accounts_rounded),
                          label: const Text('Deactivate Account'),
                          style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger, side: const BorderSide(color: AppColors.danger)),
                        ),
                      ),
                    ],

                    const SizedBox(height: 60),
                  ],
                ),
              ),
              if (_isProcessing) const LoadingWidget(message: 'Processing...'),
            ],
          );
        },
      ),
    );
  }

  String _formatDate(dynamic dateStr) {
    if (dateStr == null) return 'Never';
    try {
      final dt = DateTime.parse(dateStr.toString());
      return DateFormat('MMM dd, yyyy HH:mm').format(dt);
    } catch (_) {
      return 'Unknown';
    }
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.cardBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.borderColor)),
      child: child,
    );
  }
}

class _RoleChip extends StatelessWidget {
  final String role;
  const _RoleChip({required this.role});
  @override
  Widget build(BuildContext context) {
    final color = NavConfig.roleColor(role);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
      child: Text(NavConfig.roleLabel(role), style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const _StatusChip({required this.label, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.2))),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class _DetailTile extends StatelessWidget {
  final String label;
  final dynamic value;
  const _DetailTile({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          Text(value?.toString() ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}
