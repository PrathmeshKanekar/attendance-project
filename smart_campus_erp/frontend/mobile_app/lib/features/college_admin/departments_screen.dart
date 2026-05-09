import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../core/widgets/error_widget.dart';
import '../../../core/widgets/empty_state_widget.dart';
import 'providers/academic_providers.dart';

class DepartmentsScreen extends ConsumerWidget {
  const DepartmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(departmentsProvider);

    return AppLayout(
      title  : 'Departments',
      actions: [
        IconButton(
          icon     : const Icon(Icons.refresh_rounded),
          onPressed: () => ref.invalidate(departmentsProvider),
          tooltip  : 'Refresh',
        ),
      ],
      fab: FloatingActionButton.extended(
        onPressed : () => _showDeptDialog(context, ref, null),
        icon      : const Icon(Icons.add),
        label     : const Text('Add Department'),
        backgroundColor: AppColors.primaryLight,
      ),
      child: async.when(
        loading: () => const LoadingWidget(message: 'Loading departments...'),
        error  : (e, _) => AppErrorWidget(
          message: e.toString(),
          onRetry: () => ref.invalidate(departmentsProvider),
        ),
        data   : (depts) {
          if (depts.isEmpty) {
            return const EmptyStateWidget(
              message : 'No departments yet',
              icon    : Icons.apartment_rounded,
              subtitle: 'Tap + to add your first department',
            );
          }
          return ListView.separated(
            padding        : const EdgeInsets.all(20),
            itemCount      : depts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder    : (context, i) {
              final d = depts[i];
              return _DeptCard(
                dept   : d,
                onEdit : () => _showDeptDialog(context, ref, d),
                onDelete: () => _confirmDelete(context, ref, d),
              );
            },
          );
        },
      ),
    );
  }

  void _showDeptDialog(
    BuildContext context,
    WidgetRef    ref,
    Map<String, dynamic>? dept,
  ) {
    final nameCtrl = TextEditingController(text: dept?['name'] ?? '');
    final codeCtrl = TextEditingController(text: dept?['code'] ?? '');
    final formKey  = GlobalKey<FormState>();
    final isEdit   = dept != null;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isEdit ? 'Edit Department' : 'Add Department',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Form(
          key : formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller : nameCtrl,
                decoration : const InputDecoration(
                  labelText : 'Department Name',
                  hintText  : 'e.g. Computer Engineering',
                ),
                validator  : (v) => (v == null || v.trim().isEmpty)
                    ? 'Name is required' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller : codeCtrl,
                decoration : const InputDecoration(
                  labelText: 'Code',
                  hintText : 'e.g. CE',
                ),
                textCapitalization: TextCapitalization.characters,
                validator  : (v) => (v == null || v.trim().isEmpty)
                    ? 'Code is required' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child    : const Text('Cancel'),
          ),
          ElevatedButton(
            style    : ElevatedButton.styleFrom(
              minimumSize: const Size(90, 44),
            ),
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(ctx);

              final api  = ref.read(apiClientProvider);
              final body = {
                'name': nameCtrl.text.trim(),
                'code': codeCtrl.text.trim().toUpperCase(),
              };

              try {
                if (isEdit) {
                  await api.put('/api/departments/${dept['id']}/', data: body);
                } else {
                  await api.post('/api/departments/', data: body);
                }
                ref.invalidate(departmentsProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isEdit
                            ? 'Department updated.'
                            : 'Department created.',
                      ),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content        : Text('Error: $e'),
                      backgroundColor: AppColors.danger,
                    ),
                  );
                }
              }
            },
            child: Text(isEdit ? 'Save' : 'Create'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    WidgetRef    ref,
    Map<String, dynamic> dept,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title  : const Text('Delete Department'),
        shape  : RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        content: Text(
          'Are you sure you want to delete "${dept['name']}"? '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child    : const Text('Cancel'),
          ),
          ElevatedButton(
            style    : ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              minimumSize    : const Size(90, 44),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref
                    .read(apiClientProvider)
                    .delete('/api/departments/${dept['id']}/');
                ref.invalidate(departmentsProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content        : Text('Department deleted.'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content        : Text('Error: $e'),
                      backgroundColor: AppColors.danger,
                    ),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _DeptCard extends StatelessWidget {
  final Map<String, dynamic> dept;
  final VoidCallback         onEdit;
  final VoidCallback         onDelete;

  const _DeptCard({
    required this.dept,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding   : const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color       : AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border      : Border.all(color: AppColors.borderColor),
      ),
      child: Row(
        children: [
          Container(
            width : 46,
            height: 46,
            decoration: BoxDecoration(
              color       : AppColors.primaryLight.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.apartment_rounded,
              color: AppColors.primaryLight,
              size : 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dept['name']?.toString() ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize  : 15,
                    color     : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _Chip(
                      label: dept['code']?.toString() ?? '',
                      color: AppColors.primaryLight,
                    ),
                    if (dept['hod_name'] != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        'HOD: ${dept['hod_name']}',
                        style: const TextStyle(
                          color  : AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon     : const Icon(Icons.edit_rounded,
                color: AppColors.textSecondary, size: 20),
            onPressed: onEdit,
            tooltip  : 'Edit',
          ),
          IconButton(
            icon     : const Icon(Icons.delete_outline_rounded,
                color: AppColors.danger, size: 20),
            onPressed: onDelete,
            tooltip  : 'Delete',
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color  color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color       : color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color    : color,
          fontSize : 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
