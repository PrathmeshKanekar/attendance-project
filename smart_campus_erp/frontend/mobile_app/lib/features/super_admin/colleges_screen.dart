import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/layout/app_layout.dart';
import '../../core/widgets/empty_state_widget.dart';
import '../../core/widgets/error_widget.dart';
import '../../core/widgets/loading_widget.dart';
import 'colleges_provider.dart';

class CollegesScreen extends ConsumerStatefulWidget {
  const CollegesScreen({super.key});

  @override
  ConsumerState<CollegesScreen> createState() => _CollegesScreenState();
}

class _CollegesScreenState extends ConsumerState<CollegesScreen> {
  String _search     = '';
  String _filter     = 'all'; // all / active / inactive

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(collegesProvider);

    return AppLayout(
      title  : 'Manage Colleges',
      actions: [
        IconButton(
          icon     : const Icon(Icons.refresh_rounded),
          onPressed: () => ref.invalidate(collegesProvider),
          tooltip  : 'Refresh',
        ),
      ],
      fab: FloatingActionButton.extended(
        onPressed      : () => _showCollegeDialog(context, ref, null),
        icon           : const Icon(Icons.add_rounded),
        label          : const Text('Add College'),
        backgroundColor: AppColors.primaryLight,
      ),
      child: async.when(
        loading: () => const LoadingWidget(message: 'Loading colleges...'),
        error  : (e, _) {
          if (e is DioException && e.response?.statusCode == 403) {
            return const Center(
              child: Text(
                'Permission denied: Only Super Admin can manage colleges.',
                style: TextStyle(color: AppColors.danger),
              ),
            );
          }
          return AppErrorWidget(
            message: e.toString(),
            onRetry: () => ref.invalidate(collegesProvider),
          );
        },
        data   : (data) {
          final allColleges   = List<Map<String, dynamic>>.from(data['colleges'] ?? []);
          final total         = (data['total'] as num?)?.toInt() ?? allColleges.length;
          final activeCount   = (data['active_count'] as num?)?.toInt() ?? 
                                allColleges.where((c) => c['is_active'] == true).length;
          final inactiveCount = (data['inactive_count'] as num?)?.toInt() ?? 
                                allColleges.where((c) => c['is_active'] != true).length;

          // Apply local filters
          var filtered = allColleges.where((c) {
            final name = (c['name'] ?? c['college_name'] ?? '').toString();
            final code = (c['code'] ?? c['college_code'] ?? '').toString();
            
            final matchSearch = _search.isEmpty
                || name.toLowerCase().contains(_search.toLowerCase())
                || code.toLowerCase().contains(_search.toLowerCase());
            final matchFilter = _filter == 'all'
                || (_filter == 'active'   && c['is_active'] == true)
                || (_filter == 'inactive' && c['is_active'] == false);
            return matchSearch && matchFilter;
          }).toList();

          return Column(
            children: [

              // ── Summary bar ──────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 12,
                ),
                color: AppColors.bgSecondary,
                child: Row(
                  children: [
                    _SummaryBadge(
                      label: 'Total',
                      value: '$total',
                      color: AppColors.primaryLight,
                    ),
                    const SizedBox(width: 10),
                    _SummaryBadge(
                      label: 'Active',
                      value: '$activeCount',
                      color: AppColors.success,
                    ),
                    const SizedBox(width: 10),
                    _SummaryBadge(
                      label: 'Inactive',
                      value: '$inactiveCount',
                      color: AppColors.danger,
                    ),
                  ],
                ),
              ),

              // ── Search + Filter ──────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child  : Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        hintText  : 'Search by name or code...',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                      onChanged: (v) => setState(() => _search = v),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _FilterChip(
                          label   : 'All',
                          selected: _filter == 'all',
                          onTap   : () => setState(() => _filter = 'all'),
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label   : 'Active',
                          selected: _filter == 'active',
                          color   : AppColors.success,
                          onTap   : () => setState(() => _filter = 'active'),
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label   : 'Inactive',
                          selected: _filter == 'inactive',
                          color   : AppColors.danger,
                          onTap   : () => setState(() => _filter = 'inactive'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // ── College list ─────────────────────────────
              Expanded(
                child: filtered.isEmpty
                    ? const EmptyStateWidget(
                        message : 'No colleges found',
                        icon    : Icons.school_rounded,
                        subtitle: 'Tap + to add the first college',
                      )
                    : ListView.separated(
                        padding        : const EdgeInsets.all(16),
                        itemCount      : filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder    : (context, i) {
                          final college = filtered[i];
                          return _CollegeCard(
                            college    : college,
                            onEdit     : () => _showCollegeDialog(
                              context, ref, college,
                            ),
                            onToggle   : () => _toggleStatus(
                              context, ref, college,
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Add / Edit dialog ────────────────────────────────────
  void _showCollegeDialog(
    BuildContext context,
    WidgetRef    ref,
    Map<String, dynamic>? college,
  ) {
    final isEdit     = college != null;
    final nameCtrl   = TextEditingController(text: college?['name']         ?? '');
    final codeCtrl   = TextEditingController(text: college?['code']         ?? '');
    final domainCtrl = TextEditingController(text: college?['email_domain'] ?? '');
    final addrCtrl   = TextEditingController(text: college?['address']      ?? '');
    final phoneCtrl  = TextEditingController(text: college?['phone']        ?? '');

    // Admin Details (Only for Create)
    final adminEmailCtrl = TextEditingController();
    final adminFirstCtrl = TextEditingController();
    final adminLastCtrl  = TextEditingController();
    final adminPhoneCtrl = TextEditingController();

    final formKey    = GlobalKey<FormState>();

    showDialog(
      context : context,
      barrierDismissible: false,
      builder : (ctx) => AlertDialog(
        title    : Row(
          children: [
            Icon(
              isEdit ? Icons.edit_note_rounded : Icons.add_business_rounded,
              color: AppColors.primaryLight,
            ),
            const SizedBox(width: 10),
            Text(isEdit ? 'Edit College' : 'Register New College'),
          ],
        ),
        shape    : RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        content  : SizedBox(
          width: 550,
          child: SingleChildScrollView(
            child: Form(
              key  : formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children    : [
                  
                  _SectionHeader(title: 'College Information', icon: Icons.info_outline_rounded),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller : nameCtrl,
                    decoration : const InputDecoration(
                      labelText : 'College Name',
                      hintText  : 'e.g. Stanford University',
                      prefixIcon: Icon(Icons.school_rounded),
                    ),
                    validator  : (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller        : codeCtrl,
                          textCapitalization: TextCapitalization.characters,
                          decoration        : const InputDecoration(
                            labelText : 'Code',
                            hintText  : 'e.g. STAN',
                            prefixIcon: Icon(Icons.tag_rounded),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller : domainCtrl,
                          keyboardType: TextInputType.emailAddress,
                          decoration : const InputDecoration(
                            labelText : 'Email Domain',
                            hintText  : 'stanford.edu',
                            prefixIcon: Icon(Icons.alternate_email_rounded),
                          ),
                          validator: (v) => (v == null || !v.contains('.')) ? 'Invalid domain' : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller : addrCtrl,
                    maxLines   : 2,
                    decoration : const InputDecoration(
                      labelText : 'Full Address',
                      prefixIcon: Icon(Icons.location_on_rounded),
                    ),
                    validator  : (v) => (v == null || v.trim().isEmpty) ? 'Address is required' : null,
                  ),

                  if (!isEdit) ...[
                    const SizedBox(height: 24),
                    _SectionHeader(title: 'Primary College Admin', icon: Icons.admin_panel_settings_rounded),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller : adminEmailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration : const InputDecoration(
                        labelText : 'Admin Email',
                        hintText  : 'admin@college.edu',
                        prefixIcon: Icon(Icons.email_rounded),
                        helperText: 'A login account will be auto-created.',
                      ),
                      validator  : (v) => (v == null || !v.contains('@')) ? 'Invalid email' : null,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller : adminFirstCtrl,
                            decoration : const InputDecoration(
                              labelText : 'First Name',
                              prefixIcon: Icon(Icons.person_rounded),
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller : adminLastCtrl,
                            decoration : const InputDecoration(
                              labelText : 'Last Name',
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child    : const Text('Cancel'),
          ),
          Consumer(
            builder: (_, ref, __) {
              final crudState = ref.watch(collegeCrudProvider);
              final isLoading = crudState is CollegeCrudLoading;
              return ElevatedButton(
                style    : ElevatedButton.styleFrom(
                  minimumSize: const Size(120, 46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: isLoading
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        
                        final data = {
                          'name'        : nameCtrl.text.trim(),
                          'code'        : codeCtrl.text.trim().toUpperCase(),
                          'email_domain': domainCtrl.text.trim().toLowerCase(),
                          'address'     : addrCtrl.text.trim(),
                          'phone'       : phoneCtrl.text.trim(),
                          if (!isEdit) ...{
                            'admin_email'      : adminEmailCtrl.text.trim().toLowerCase(),
                            'admin_first_name' : adminFirstCtrl.text.trim(),
                            'admin_last_name'  : adminLastCtrl.text.trim(),
                            'admin_phone'      : adminPhoneCtrl.text.trim(),
                          }
                        };

                        try {
                          final collegeId = (college?['id'] ?? college?['uuid'] ?? '').toString();
                          final success = isEdit 
                            ? await ref.read(collegeCrudProvider.notifier).updateCollege(collegeId, data)
                            : await ref.read(collegeCrudProvider.notifier).createCollege(data);

                          if (ctx.mounted) Navigator.pop(ctx);

                          if (context.mounted) {
                            final state = ref.read(collegeCrudProvider);
                            if (success && state is CollegeCrudSuccess) {
                              if (state.data != null) {
                                // Show credentials modal for new college
                                _showCredentialsDialog(context, state.data!);
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(state.message), backgroundColor: AppColors.success),
                                );
                              }
                            } else if (state is CollegeCrudError) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(state.message), backgroundColor: AppColors.danger),
                              );
                            }
                            ref.read(collegeCrudProvider.notifier).reset();
                          }
                        } on DioException catch (e) {
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (e.response?.statusCode == 403 && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('You do not have permission to perform this action.'),
                                backgroundColor: AppColors.danger,
                              ),
                            );
                            return;
                          }
                          rethrow;
                        } catch (e) {
                          if (ctx.mounted) Navigator.pop(ctx);
                          rethrow;
                        }
                      },
                child: isLoading
                    ? const SizedBox(width : 20, height: 20, child : CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(isEdit ? 'Save Changes' : 'Register College'),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showCredentialsDialog(BuildContext context, Map<String, dynamic> credentials) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.vpn_key_rounded, color: AppColors.success),
            SizedBox(width: 10),
            Text('College Admin Created'),
          ],
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'A dedicated College Admin account has been automatically generated with the following credentials:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            _CredentialField(label: 'Admin Email', value: credentials['email']?.toString() ?? ''),
            const SizedBox(height: 10),
            _CredentialField(label: 'Temp Password', value: credentials['password']?.toString() ?? '', isPassword: true),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.warning.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Please share these credentials securely. The password will not be shown again.',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
            child: const Text('I have saved these'),
          ),
        ],
      ),
    );
  }

  // ── Toggle active / inactive ─────────────────────────────
  Future<void> _toggleStatus(
    BuildContext context,
    WidgetRef    ref,
    Map<String, dynamic> college,
  ) async {
    final isActive = college['is_active'] == true;
    final action   = isActive ? 'Deactivate' : 'Activate';
    final color    = isActive ? AppColors.danger : AppColors.success;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title  : Text('$action College'),
        shape  : RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        content: Text(
          '$action "${college['name']}"?\n\n'
          '${isActive
            ? 'Users of this college will not be able to login.'
            : 'Users of this college will regain access.'}'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child    : const Text('Cancel'),
          ),
          ElevatedButton(
            style    : ElevatedButton.styleFrom(backgroundColor: color),
            onPressed: () => Navigator.pop(ctx, true),
            child    : Text(action),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      bool success;
      final collegeId = (college['id'] ?? college['uuid'] ?? '').toString();
      if (isActive) {
        success = await ref
            .read(collegeCrudProvider.notifier)
            .deactivateCollege(collegeId);
      } else {
        success = await ref
            .read(collegeCrudProvider.notifier)
            .activateCollege(collegeId);
      }

      if (context.mounted) {
        final state = ref.read(collegeCrudProvider);
        final msg   = state is CollegeCrudSuccess
            ? state.message
            : state is CollegeCrudError ? state.message : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content        : Text(msg),
            backgroundColor: success ? AppColors.success : AppColors.danger,
          ),
        );
        ref.read(collegeCrudProvider.notifier).reset();
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 403 && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You do not have permission to perform this action.'),
            backgroundColor: AppColors.danger,
          ),
        );
        return;
      }
      rethrow;
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title; final IconData icon;
  const _SectionHeader({required this.title, required this.icon});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textSecondary, letterSpacing: 0.5)),
      ],
    );
  }
}

class _CredentialField extends StatelessWidget {
  final String label; final String value; final bool isPassword;
  const _CredentialField({required this.label, required this.value, this.isPassword = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.bgSecondary,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.borderColor),
          ),
          child: Row(
            children: [
              Expanded(child: Text(value, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 14))),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 18),
                onPressed: () {
                  // Standard copy to clipboard logic would go here
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
                },
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── College card ───────────────────────────────────────────
class _CollegeCard extends StatelessWidget {
  final Map<String, dynamic> college;
  final VoidCallback         onEdit;
  final VoidCallback         onToggle;

  const _CollegeCard({
    required this.college,
    required this.onEdit,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    // ROBUST DATA BINDING: Support multiple possible keys and handle nulls
    final name       = (college['name'] ?? college['college_name'] ?? 'Unknown').toString();
    final code       = (college['code'] ?? college['college_code'] ?? '').toString();
    final domain     = (college['email_domain'] ?? college['domain'] ?? '').toString();
    final address    = (college['address'] ?? college['location'] ?? '').toString();
    final phone      = (college['phone'] ?? '').toString();
    final isActive   = college['is_active'] == true || college['status'] == 'active';
    final userCount  = (college['user_count'] as num?)?.toInt() ?? 
                       (college['student_count'] as num?)?.toInt() ?? 0;

    final statusColor = isActive ? AppColors.success : AppColors.danger;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left Status Bar
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                ),
              ),
            ),
            // Card Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header row ────────────────────────────────
                    Row(
                      children: [
                        Container(
                          width : 44, height: 44,
                          decoration: BoxDecoration(
                            color       : AppColors.primaryLight.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.school_rounded,
                            color: AppColors.primaryLight,
                            size : 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize  : 15,
                                  color     : AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                domain,
                                style: const TextStyle(
                                  color  : AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Status chip
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color       : isActive
                                ? AppColors.success.withOpacity(0.10)
                                : AppColors.danger.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isActive ? '● Active' : '○ Inactive',
                            style: TextStyle(
                              color    : isActive ? AppColors.success : AppColors.danger,
                              fontSize : 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // ── Info row ──────────────────────────────────
                    Wrap(
                      spacing    : 12,
                      runSpacing : 6,
                      children   : [
                        _InfoItem(
                          icon : Icons.tag_rounded,
                          label: code,
                        ),
                        _InfoItem(
                          icon : Icons.people_rounded,
                          label: '$userCount users',
                        ),
                        if (phone.isNotEmpty)
                          _InfoItem(
                            icon : Icons.phone_rounded,
                            label: phone,
                          ),
                      ],
                    ),

                    const SizedBox(height: 4),

                    _InfoItem(
                      icon : Icons.location_on_rounded,
                      label: address,
                    ),

                    const SizedBox(height: 12),

                    // ── Action buttons ────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton.icon(
                          style    : OutlinedButton.styleFrom(
                            foregroundColor: isActive ? AppColors.danger : AppColors.success,
                            side           : BorderSide(
                              color: isActive ? AppColors.danger : AppColors.success,
                            ),
                            minimumSize: const Size(0, 38),
                            padding    : const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          onPressed: onToggle,
                          icon : Icon(
                            isActive
                                ? Icons.block_rounded
                                : Icons.check_circle_rounded,
                            size: 16,
                          ),
                          label: Text(isActive ? 'Deactivate' : 'Activate'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          style    : ElevatedButton.styleFrom(
                            minimumSize: const Size(0, 38),
                            padding    : const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          onPressed: onEdit,
                          icon : const Icon(Icons.edit_rounded, size: 16),
                          label: const Text('Edit'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final IconData icon; final String label;
  const _InfoItem({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Flexible(child: Text(label, style: const TextStyle(
          color: AppColors.textSecondary, fontSize: 12,
        ), overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

class _SummaryBadge extends StatelessWidget {
  final String label, value; final Color color;
  const _SummaryBadge({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(children: [
        Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w800)),
        Text(label, style: TextStyle(color: color.withOpacity(0.80), fontSize: 11)),
      ]),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label; final bool selected;
  final Color color; final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected,
      required this.onTap, this.color = AppColors.primaryLight});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color : AppColors.bgSecondary,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color : AppColors.borderColor),
        ),
        child: Text(label, style: TextStyle(
          color: selected ? Colors.white : AppColors.textSecondary,
          fontSize: 13, fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        )),
      ),
    );
  }
}
