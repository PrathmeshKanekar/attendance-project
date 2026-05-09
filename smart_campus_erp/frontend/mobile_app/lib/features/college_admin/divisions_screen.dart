import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../core/widgets/error_widget.dart';
import '../../../core/widgets/empty_state_widget.dart';
import 'providers/academic_providers.dart';

class DivisionsScreen extends ConsumerWidget {
  const DivisionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(divisionsProvider);
    final coursesAsync = ref.watch(coursesProvider);
    final academicYearsAsync = ref.watch(academicYearsProvider);

    return AppLayout(
      title  : 'Divisions',
      actions: [
        IconButton(
          icon     : const Icon(Icons.refresh_rounded),
          onPressed: () => ref.invalidate(divisionsProvider),
          tooltip  : 'Refresh',
        ),
      ],
      fab: FloatingActionButton.extended(
        onPressed : () => _showDivisionDialog(context, ref, coursesAsync.value ?? [], academicYearsAsync.value ?? [], null),
        icon      : const Icon(Icons.add),
        label     : const Text('Add Division'),
        backgroundColor: AppColors.primaryLight,
      ),
      child: async.when(
        loading: () => const LoadingWidget(message: 'Loading divisions...'),
        error  : (e, _) => AppErrorWidget(
          message: e.toString(),
          onRetry: () => ref.invalidate(divisionsProvider),
        ),
        data   : (divisions) {
          if (divisions.isEmpty) {
            return const EmptyStateWidget(
              message : 'No divisions yet',
              icon    : Icons.group_work_rounded,
              subtitle: 'Tap + to add your first division',
            );
          }
          return ListView.separated(
            padding        : const EdgeInsets.all(20),
            itemCount      : divisions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder    : (context, i) {
              final d = divisions[i];
              return _DivisionCard(
                division: d,
                onEdit : () => _showDivisionDialog(context, ref, coursesAsync.value ?? [], academicYearsAsync.value ?? [], d),
                onDelete: () => _confirmDelete(context, ref, d),
              );
            },
          );
        },
      ),
    );
  }

  void _showDivisionDialog(
    BuildContext context,
    WidgetRef    ref,
    List<Map<String, dynamic>> courses,
    List<Map<String, dynamic>> years,
    Map<String, dynamic>? division,
  ) {
    final nameCtrl = TextEditingController(text: division?['name'] ?? '');
    final capacityCtrl = TextEditingController(text: (division?['capacity'] ?? 60).toString());
    String? selectedCourseId = division?['course'] != null ? division!['course'].toString() : null;
    String? selectedYearId = division?['academic_year'] != null ? division!['academic_year'].toString() : null;
    int selectedYearOfStudy = division?['year_of_study'] ?? 1;
    final formKey  = GlobalKey<FormState>();
    final isEdit   = division != null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            isEdit ? 'Edit Division' : 'Add Division',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: SingleChildScrollView(
            child: Form(
              key : formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller : nameCtrl,
                    decoration : const InputDecoration(
                      labelText : 'Division Name',
                      hintText  : 'e.g. A, B',
                    ),
                    validator  : (v) => (v == null || v.trim().isEmpty)
                        ? 'Name is required' : null,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: selectedCourseId,
                    hint: const Text('Select Course'),
                    items: courses.map((c) {
                      return DropdownMenuItem<String>(
                        value: c['id'].toString(),
                        child: Text(c['name'] ?? ''),
                      );
                    }).toList(),
                    onChanged: isEdit ? null : (v) => setState(() => selectedCourseId = v),
                    validator: (v) => v == null ? 'Course is required' : null,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: selectedYearId,
                    hint: const Text('Select Academic Year'),
                    items: years.map((y) {
                      return DropdownMenuItem<String>(
                        value: y['id'].toString(),
                        child: Text(y['name'] ?? ''),
                      );
                    }).toList(),
                    onChanged: isEdit ? null : (v) => setState(() => selectedYearId = v),
                    validator: (v) => v == null ? 'Academic Year is required' : null,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<int>(
                    value: selectedYearOfStudy,
                    decoration: const InputDecoration(labelText: 'Year of Study'),
                    items: [1, 2, 3, 4].map((y) {
                      return DropdownMenuItem<int>(
                        value: y,
                        child: Text('Year $y'),
                      );
                    }).toList(),
                    onChanged: (v) => setState(() => selectedYearOfStudy = v ?? 1),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: capacityCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Capacity',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Capacity is required' : null,
                  ),
                ],
              ),
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
                  if (selectedCourseId != null) 'course': selectedCourseId,
                  if (selectedYearId != null) 'academic_year': selectedYearId,
                  'year_of_study': selectedYearOfStudy,
                  'capacity': int.tryParse(capacityCtrl.text.trim()) ?? 60,
                };

                try {
                  if (isEdit) {
                    await api.put('/api/divisions/${division['id']}/', data: body);
                  } else {
                    await api.post('/api/divisions/', data: body);
                  }
                  ref.invalidate(divisionsProvider);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isEdit
                              ? 'Division updated.'
                              : 'Division created.',
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
    ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    WidgetRef    ref,
    Map<String, dynamic> division,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title  : const Text('Delete Division'),
        shape  : RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        content: Text(
          'Are you sure you want to delete division "${division['name']}"? '
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
                    .delete('/api/divisions/${division['id']}/');
                ref.invalidate(divisionsProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content        : Text('Division deleted.'),
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

class _DivisionCard extends StatelessWidget {
  final Map<String, dynamic> division;
  final VoidCallback         onEdit;
  final VoidCallback         onDelete;

  const _DivisionCard({
    required this.division,
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
              color       : AppColors.accent.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.group_work_rounded,
              color: AppColors.accent,
              size : 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Year ${division['year_of_study'] ?? 1} - Division ${division['name'] ?? ''}',
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
                      label: division['name']?.toString() ?? '',
                      color: AppColors.primaryLight,
                    ),
                    const SizedBox(width: 8),
                    _Chip(
                      label: 'Y${division['year_of_study'] ?? 1}',
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${division['course_name'] ?? ''} · ${division['academic_year_name'] ?? ''}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${division['student_count'] ?? 0} students enrolled',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
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
