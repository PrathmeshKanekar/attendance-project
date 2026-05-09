import 'package:flutter/material.dart';
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
        error  : (e, _) => AppErrorWidget(
          message: e.toString(),
          onRetry: () => ref.invalidate(collegesProvider),
        ),
        data   : (data) {
          final allColleges = List<Map<String, dynamic>>.from(
            data['colleges'] as List,
          );
          final total         = data['total']         as int? ?? 0;
          final activeCount   = data['active_count']  as int? ?? 0;
          final inactiveCount = data['inactive_count']as int? ?? 0;

          // Apply local filters
          var filtered = allColleges.where((c) {
            final matchSearch = _search.isEmpty
                || c['name'].toString().toLowerCase()
                    .contains(_search.toLowerCase())
                || c['code'].toString().toLowerCase()
                    .contains(_search.toLowerCase());
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
    final formKey    = GlobalKey<FormState>();

    showDialog(
      context : context,
      builder : (ctx) => AlertDialog(
        title    : Text(
          isEdit ? 'Edit College' : 'Add New College',
          style  : const TextStyle(fontWeight: FontWeight.bold),
        ),
        shape    : RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        content  : SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Form(
              key  : formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children    : [
                  TextFormField(
                    controller : nameCtrl,
                    decoration : const InputDecoration(
                      labelText : 'College Name',
                      hintText  : 'e.g. MIT College of Engineering',
                      prefixIcon: Icon(Icons.school_rounded),
                    ),
                    validator  : (v) => (v == null || v.trim().isEmpty)
                        ? 'Name is required' : null,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller        : codeCtrl,
                          textCapitalization: TextCapitalization.characters,
                          decoration        : const InputDecoration(
                            labelText : 'College Code',
                            hintText  : 'e.g. MIT',
                            prefixIcon: Icon(Icons.tag_rounded),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Code required' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller : phoneCtrl,
                          keyboardType: TextInputType.phone,
                          decoration : const InputDecoration(
                            labelText : 'Phone',
                            hintText  : '020-12345678',
                            prefixIcon: Icon(Icons.phone_rounded),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller : domainCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration : const InputDecoration(
                      labelText : 'Email Domain',
                      hintText  : 'e.g. mit.edu',
                      prefixIcon: Icon(Icons.alternate_email_rounded),
                      helperText: 'Students/staff will register with this domain',
                    ),
                    validator  : (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Email domain is required';
                      }
                      if (!v.contains('.')) {
                        return 'Enter a valid domain (e.g. college.edu)';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller : addrCtrl,
                    maxLines   : 3,
                    decoration : const InputDecoration(
                      labelText : 'Address',
                      hintText  : '123 College Road, City, State PIN',
                      prefixIcon: Icon(Icons.location_on_rounded),
                    ),
                    validator  : (v) => (v == null || v.trim().isEmpty)
                        ? 'Address is required' : null,
                  ),
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
                  minimumSize: const Size(100, 44),
                ),
                onPressed: isLoading
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        Navigator.pop(ctx);

                        final data = {
                          'name'        : nameCtrl.text.trim(),
                          'code'        : codeCtrl.text.trim().toUpperCase(),
                          'email_domain': domainCtrl.text.trim().toLowerCase(),
                          'address'     : addrCtrl.text.trim(),
                          'phone'       : phoneCtrl.text.trim(),
                        };

                        bool success;
                        if (isEdit) {
                          success = await ref
                              .read(collegeCrudProvider.notifier)
                              .updateCollege(college['id'].toString(), data);
                        } else {
                          success = await ref
                              .read(collegeCrudProvider.notifier)
                              .createCollege(data);
                        }

                        if (context.mounted) {
                          final state = ref.read(collegeCrudProvider);
                          final msg   = state is CollegeCrudSuccess
                              ? state.message
                              : state is CollegeCrudError
                                  ? state.message
                                  : '';
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content        : Text(msg),
                              backgroundColor: success
                                  ? AppColors.success
                                  : AppColors.danger,
                            ),
                          );
                          ref.read(collegeCrudProvider.notifier).reset();
                        }
                      },
                child: isLoading
                    ? const SizedBox(
                        width : 20, height: 20,
                        child : CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white,
                        ),
                      )
                    : Text(isEdit ? 'Save' : 'Create'),
              );
            },
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

    bool success;
    if (isActive) {
      success = await ref
          .read(collegeCrudProvider.notifier)
          .deactivateCollege(college['id'].toString());
    } else {
      success = await ref
          .read(collegeCrudProvider.notifier)
          .activateCollege(college['id'].toString());
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
    // CRITICAL FIX: safe string conversion for all fields
    final name       = college['name']?.toString()         ?? 'Unknown';
    final code       = college['code']?.toString()         ?? '';
    final domain     = college['email_domain']?.toString() ?? '';
    final address    = college['address']?.toString()      ?? '';
    final phone      = college['phone']?.toString()        ?? '';
    final isActive   = college['is_active'] == true;
    final userCount  = (college['user_count'] as num?)?.toInt() ?? 0;


    return Container(
      padding   : const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color       : AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border      : Border(
          left  : BorderSide(
            color: isActive ? AppColors.success : AppColors.danger,
            width: 4,
          ),
          top   : const BorderSide(color: AppColors.borderColor),
          right : const BorderSide(color: AppColors.borderColor),
          bottom: const BorderSide(color: AppColors.borderColor),
        ),
      ),
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
