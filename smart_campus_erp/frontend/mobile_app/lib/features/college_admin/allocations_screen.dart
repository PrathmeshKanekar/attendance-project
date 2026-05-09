import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../core/widgets/error_widget.dart';
import '../../../core/widgets/empty_state_widget.dart';
import 'providers/academic_providers.dart';

class AllocationsScreen extends ConsumerWidget {
  const AllocationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(allocationsProvider);
    final subjectsAsync = ref.watch(subjectsProvider);
    final teachersAsync = ref.watch(teachersProvider);
    final divisionsAsync = ref.watch(divisionsProvider);
    final academicYearsAsync = ref.watch(academicYearsProvider);

    return AppLayout(
      title  : 'Subject Allocations',
      actions: [
        IconButton(
          icon     : const Icon(Icons.refresh_rounded),
          onPressed: () => ref.invalidate(allocationsProvider),
          tooltip  : 'Refresh',
        ),
      ],
      fab: FloatingActionButton.extended(
        onPressed : () => _showAllocationDialog(
          context, ref,
          subjectsAsync.value ?? [],
          teachersAsync.value ?? [],
          divisionsAsync.value ?? [],
          academicYearsAsync.value ?? [],
        ),
        icon      : const Icon(Icons.add),
        label     : const Text('Allocate Subject'),
        backgroundColor: AppColors.primaryLight,
      ),
      child: async.when(
        loading: () => const LoadingWidget(message: 'Loading allocations...'),
        error  : (e, _) => AppErrorWidget(
          message: e.toString(),
          onRetry: () => ref.invalidate(allocationsProvider),
        ),
        data   : (allocations) {
          if (allocations.isEmpty) {
            return const EmptyStateWidget(
              message : 'No subject allocations yet',
              icon    : Icons.assignment_rounded,
              subtitle: 'Tap + to assign a teacher to a subject',
            );
          }
          return ListView.separated(
            padding        : const EdgeInsets.all(20),
            itemCount      : allocations.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder    : (context, i) {
              final a = allocations[i];
              return _AllocationCard(
                allocation: a,
                onDelete  : () => _confirmDelete(context, ref, a),
              );
            },
          );
        },
      ),
    );
  }

  void _showAllocationDialog(
    BuildContext context,
    WidgetRef    ref,
    List<Map<String, dynamic>> subjects,
    List<Map<String, dynamic>> teachers,
    List<Map<String, dynamic>> divisions,
    List<Map<String, dynamic>> years,
  ) {
    String? selectedSubjectId;
    String? selectedTeacherId;
    String? selectedDivisionId;
    String? selectedYearId;

    // Pre-select current academic year
    final currentYear = years.firstWhere(
      (y) => y['is_current'] == true,
      orElse: () => years.isNotEmpty ? years.first : {},
    );
    if (currentYear.isNotEmpty) {
      selectedYearId = currentYear['id']?.toString();
    }

    final formKey  = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text(
            'New Subject Allocation',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: SingleChildScrollView(
            child: Form(
              key : formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedSubjectId,
                    hint: const Text('Select Subject'),
                    items: subjects.map((s) {
                      return DropdownMenuItem<String>(
                        value: s['id'].toString(),
                        child: Text('${s['name']} (${s['code']})'),
                      );
                    }).toList(),
                    onChanged: (v) => setState(() => selectedSubjectId = v),
                    validator: (v) => v == null ? 'Subject is required' : null,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: selectedTeacherId,
                    hint: const Text('Select Teacher'),
                    items: teachers.map((t) {
                      return DropdownMenuItem<String>(
                        value: t['id'].toString(),
                        child: Text('${t['first_name'] ?? ''} ${t['last_name'] ?? ''}'),
                      );
                    }).toList(),
                    onChanged: (v) => setState(() => selectedTeacherId = v),
                    validator: (v) => v == null ? 'Teacher is required' : null,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: selectedDivisionId,
                    hint: const Text('Select Division'),
                    items: divisions.map((d) {
                      return DropdownMenuItem<String>(
                        value: d['id'].toString(),
                        child: Text('Div ${d['name']} (${d['course_code'] ?? ''} Y${d['year_of_study']})'),
                      );
                    }).toList(),
                    onChanged: (v) => setState(() => selectedDivisionId = v),
                    validator: (v) => v == null ? 'Division is required' : null,
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
                    onChanged: (v) => setState(() => selectedYearId = v),
                    validator: (v) => v == null ? 'Academic Year is required' : null,
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
                  'subject': selectedSubjectId,
                  'teacher': selectedTeacherId,
                  'division': selectedDivisionId,
                  'academic_year': selectedYearId,
                };

                try {
                  await api.post('/api/allocations/', data: body);
                  ref.invalidate(allocationsProvider);

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Subject allocated! Would you like to enroll students now?'),
                        backgroundColor: AppColors.success,
                        action: SnackBarAction(
                          label: 'Enroll',
                          textColor: Colors.white,
                          onPressed: () {
                            context.push('/admin/enrollments');
                          },
                        ),
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
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    WidgetRef    ref,
    Map<String, dynamic> allocation,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title  : const Text('Delete Allocation'),
        shape  : RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        content: Text(
          'Are you sure you want to delete allocation for "${allocation['subject_name']}"? '
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
                    .delete('/api/allocations/${allocation['id']}/');
                ref.invalidate(allocationsProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content        : Text('Allocation deleted.'),
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

class _AllocationCard extends StatelessWidget {
  final Map<String, dynamic> allocation;
  final VoidCallback         onDelete;

  const _AllocationCard({
    required this.allocation,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding   : const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color       : AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border      : const Border(
          left: BorderSide(color: Colors.green, width: 4),
          top: BorderSide(color: AppColors.borderColor),
          right: BorderSide(color: AppColors.borderColor),
          bottom: BorderSide(color: AppColors.borderColor),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${allocation['subject_name'] ?? ''} (${allocation['subject_code'] ?? ''})',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize  : 16,
                    color     : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Teacher: ${allocation['teacher_name'] ?? ''}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize  : 13,
                    color     : AppColors.textPrimary,
                  ),
                ),
                if (allocation['teacher_email'] != null)
                  Text(
                    allocation['teacher_email'],
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                  'Division: ${allocation['division_name'] ?? ''} · Year ${allocation['division_year'] ?? 1} · ${allocation['academic_year_name'] ?? ''}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              _Chip(
                label: '${allocation['enrollment_count'] ?? 0} students',
                color: AppColors.primaryLight,
              ),
              IconButton(
                icon     : const Icon(Icons.delete_outline_rounded,
                    color: AppColors.danger, size: 20),
                onPressed: onDelete,
                tooltip  : 'Delete',
              ),
            ],
          )
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
