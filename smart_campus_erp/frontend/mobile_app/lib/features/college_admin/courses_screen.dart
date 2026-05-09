import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../core/widgets/error_widget.dart';
import '../../../core/widgets/empty_state_widget.dart';
import 'providers/academic_providers.dart';

class CoursesScreen extends ConsumerWidget {
  const CoursesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(coursesProvider);
    final departmentsAsync = ref.watch(departmentsProvider);

    return AppLayout(
      title  : 'Courses',
      actions: [
        IconButton(
          icon     : const Icon(Icons.refresh_rounded),
          onPressed: () => ref.invalidate(coursesProvider),
          tooltip  : 'Refresh',
        ),
      ],
      fab: FloatingActionButton.extended(
        onPressed : () => _showCourseDialog(context, ref, departmentsAsync.value ?? [], null),
        icon      : const Icon(Icons.add),
        label     : const Text('Add Course'),
        backgroundColor: AppColors.primaryLight,
      ),
      child: async.when(
        loading: () => const LoadingWidget(message: 'Loading courses...'),
        error  : (e, _) => AppErrorWidget(
          message: e.toString(),
          onRetry: () => ref.invalidate(coursesProvider),
        ),
        data   : (courses) {
          if (courses.isEmpty) {
            return const EmptyStateWidget(
              message : 'No courses yet',
              icon    : Icons.school_rounded,
              subtitle: 'Tap + to add your first course',
            );
          }
          return ListView.separated(
            padding        : const EdgeInsets.all(20),
            itemCount      : courses.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder    : (context, i) {
              final c = courses[i];
              return _CourseCard(
                course : c,
                onEdit : () => _showCourseDialog(context, ref, departmentsAsync.value ?? [], c),
                onDelete: () => _confirmDelete(context, ref, c),
              );
            },
          );
        },
      ),
    );
  }

  void _showCourseDialog(
    BuildContext context,
    WidgetRef    ref,
    List<Map<String, dynamic>> departments,
    Map<String, dynamic>? course,
  ) {
    final nameCtrl = TextEditingController(text: course?['name'] ?? '');
    final codeCtrl = TextEditingController(text: course?['code'] ?? '');
    String? selectedDeptId = course?['department'] != null ? course!['department'].toString() : null;
    int selectedDuration = course?['duration_years'] ?? 4;
    final formKey  = GlobalKey<FormState>();
    final isEdit   = course != null;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isEdit ? 'Edit Course' : 'Add Course',
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
                  labelText : 'Course Name',
                  hintText  : 'e.g. B.E. Computer Engineering',
                ),
                validator  : (v) => (v == null || v.trim().isEmpty)
                    ? 'Name is required' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller : codeCtrl,
                decoration : const InputDecoration(
                  labelText: 'Code',
                  hintText : 'e.g. BECE',
                ),
                textCapitalization: TextCapitalization.characters,
                validator  : (v) => (v == null || v.trim().isEmpty)
                    ? 'Code is required' : null,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: selectedDeptId,
                hint: const Text('Select Department'),
                items: departments.map((d) {
                  return DropdownMenuItem<String>(
                    value: d['id'].toString(),
                    child: Text(d['name'] ?? ''),
                  );
                }).toList(),
                onChanged: isEdit ? null : (v) => selectedDeptId = v,
                validator: (v) => v == null ? 'Department is required' : null,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                value: selectedDuration,
                hint: const Text('Duration in years'),
                items: [2, 3, 4].map((d) {
                  return DropdownMenuItem<int>(
                    value: d,
                    child: Text('$d Years'),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) selectedDuration = v;
                },
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
                if (selectedDeptId != null) 'department': selectedDeptId,
                'duration_years': selectedDuration,
              };

              try {
                if (isEdit) {
                  await api.put('/api/courses/${course['id']}/', data: body);
                } else {
                  await api.post('/api/courses/', data: body);
                }
                ref.invalidate(coursesProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isEdit
                            ? 'Course updated.'
                            : 'Course created.',
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
    Map<String, dynamic> course,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title  : const Text('Delete Course'),
        shape  : RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        content: Text(
          'Are you sure you want to delete "${course['name']}"? '
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
                    .delete('/api/courses/${course['id']}/');
                ref.invalidate(coursesProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content        : Text('Course deleted.'),
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

class _CourseCard extends StatelessWidget {
  final Map<String, dynamic> course;
  final VoidCallback         onEdit;
  final VoidCallback         onDelete;

  const _CourseCard({
    required this.course,
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
              color       : Colors.purple.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.school_rounded,
              color: Colors.purple,
              size : 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  course['name']?.toString() ?? '',
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
                      label: course['code']?.toString() ?? '',
                      color: AppColors.primaryLight,
                    ),
                    const SizedBox(width: 8),
                    _Chip(
                      label: '${course['duration_years'] ?? 4} Years',
                      color: AppColors.textSecondary,
                    ),
                    if (course['department_name'] != null) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          course['department_name'] ?? '',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
