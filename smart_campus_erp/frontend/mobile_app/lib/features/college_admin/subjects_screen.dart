import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../core/widgets/error_widget.dart';
import '../../../core/widgets/empty_state_widget.dart';
import 'providers/academic_providers.dart';

class SubjectsScreen extends ConsumerStatefulWidget {
  const SubjectsScreen({super.key});

  @override
  ConsumerState<SubjectsScreen> createState() => _SubjectsScreenState();
}

class _SubjectsScreenState extends ConsumerState<SubjectsScreen> {
  String _activeFilter = 'All';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(subjectsProvider);
    final deptsAsync = ref.watch(departmentsProvider);
    final coursesAsync = ref.watch(coursesProvider);

    return AppLayout(
      title  : 'Subjects',
      actions: [
        IconButton(
          icon     : const Icon(Icons.refresh_rounded),
          onPressed: () => ref.invalidate(subjectsProvider),
          tooltip  : 'Refresh',
        ),
      ],
      fab: FloatingActionButton.extended(
        onPressed : () => _showSubjectDialog(context, ref, deptsAsync.value ?? [], coursesAsync.value ?? [], null),
        icon      : const Icon(Icons.add),
        label     : const Text('Add Subject'),
        backgroundColor: AppColors.primaryLight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: ['All', 'Year 1', 'Year 2', 'Year 3', 'Year 4', 'Lab Only'].map((f) {
                final isSelected = _activeFilter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(f),
                    selected: isSelected,
                    onSelected: (val) {
                      if (val) setState(() => _activeFilter = f);
                    },
                    selectedColor: AppColors.primaryLight.withOpacity(0.24),
                    backgroundColor: AppColors.cardBg,
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const LoadingWidget(message: 'Loading subjects...'),
              error  : (e, _) => AppErrorWidget(
                message: e.toString(),
                onRetry: () => ref.invalidate(subjectsProvider),
              ),
              data   : (subjects) {
                final filtered = subjects.where((s) {
                  if (_activeFilter == 'All') return true;
                  if (_activeFilter == 'Lab Only') return s['is_lab'] == true;
                  if (_activeFilter.startsWith('Year')) {
                    final yr = int.tryParse(_activeFilter.split(' ').last);
                    return s['year_of_study'] == yr;
                  }
                  return true;
                }).toList();

                if (filtered.isEmpty) {
                  return const EmptyStateWidget(
                    message : 'No subjects match filter',
                    icon    : Icons.menu_book_rounded,
                    subtitle: 'Try changing your filter or tap + to add a subject',
                  );
                }
                return ListView.separated(
                  padding        : const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  itemCount      : filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder    : (context, i) {
                    final s = filtered[i];
                    return _SubjectCard(
                      subject: s,
                      onEdit : () => _showSubjectDialog(context, ref, deptsAsync.value ?? [], coursesAsync.value ?? [], s),
                      onDelete: () => _confirmDelete(context, ref, s),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showSubjectDialog(
    BuildContext context,
    WidgetRef    ref,
    List<Map<String, dynamic>> depts,
    List<Map<String, dynamic>> courses,
    Map<String, dynamic>? subject,
  ) {
    final nameCtrl = TextEditingController(text: subject?['name'] ?? '');
    final codeCtrl = TextEditingController(text: subject?['code'] ?? '');
    final creditsCtrl = TextEditingController(text: (subject?['credits'] ?? 4).toString());
    String? selectedDeptId = subject?['department'] != null ? subject!['department'].toString() : null;
    String? selectedCourseId = subject?['course'] != null ? subject!['course'].toString() : null;
    int selectedYear = subject?['year_of_study'] ?? 1;
    int selectedSem = subject?['semester'] ?? 1;
    bool isLabSubject = subject?['is_lab'] ?? false;
    final formKey  = GlobalKey<FormState>();
    final isEdit   = subject != null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            isEdit ? 'Edit Subject' : 'Add Subject',
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
                      labelText : 'Subject Name',
                    ),
                    validator  : (v) => (v == null || v.trim().isEmpty)
                        ? 'Name is required' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller : codeCtrl,
                    decoration : const InputDecoration(
                      labelText: 'Code',
                    ),
                    textCapitalization: TextCapitalization.characters,
                    validator  : (v) => (v == null || v.trim().isEmpty)
                        ? 'Code is required' : null,
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: selectedDeptId,
                    hint: const Text('Select Department'),
                    items: depts.map((d) {
                      return DropdownMenuItem<String>(
                        value: d['id'].toString(),
                        child: Text(d['name'] ?? ''),
                      );
                    }).toList(),
                    onChanged: isEdit ? null : (v) => setState(() => selectedDeptId = v),
                    validator: (v) => v == null ? 'Department is required' : null,
                  ),
                  const SizedBox(height: 10),
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
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: selectedYear,
                          decoration: const InputDecoration(labelText: 'Year'),
                          items: [1, 2, 3, 4].map((y) {
                            return DropdownMenuItem<int>(
                              value: y,
                              child: Text('Year $y'),
                            );
                          }).toList(),
                          onChanged: (v) => setState(() => selectedYear = v ?? 1),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: selectedSem,
                          decoration: const InputDecoration(labelText: 'Sem'),
                          items: List.generate(8, (index) => index + 1).map((s) {
                            return DropdownMenuItem<int>(
                              value: s,
                              child: Text('Sem $s'),
                            );
                          }).toList(),
                          onChanged: (v) => setState(() => selectedSem = v ?? 1),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller : creditsCtrl,
                    decoration : const InputDecoration(
                      labelText: 'Credits',
                    ),
                    keyboardType: TextInputType.number,
                    validator  : (v) => (v == null || v.trim().isEmpty)
                        ? 'Credits are required' : null,
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile(
                    title: const Text('Is Lab subject?'),
                    value: isLabSubject,
                    onChanged: (v) => setState(() => isLabSubject = v),
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
                  'code': codeCtrl.text.trim().toUpperCase(),
                  if (selectedDeptId != null) 'department': selectedDeptId,
                  if (selectedCourseId != null) 'course': selectedCourseId,
                  'year_of_study': selectedYear,
                  'semester': selectedSem,
                  'credits': int.tryParse(creditsCtrl.text.trim()) ?? 4,
                  'is_lab': isLabSubject,
                };

                try {
                  if (isEdit) {
                    await api.put('/api/subjects/${subject['id']}/', data: body);
                  } else {
                    await api.post('/api/subjects/', data: body);
                  }
                  ref.invalidate(subjectsProvider);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isEdit
                              ? 'Subject updated.'
                              : 'Subject created.',
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
    Map<String, dynamic> subject,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title  : const Text('Delete Subject'),
        shape  : RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        content: Text(
          'Are you sure you want to delete "${subject['name']}"? '
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
                    .delete('/api/subjects/${subject['id']}/');
                ref.invalidate(subjectsProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content        : Text('Subject deleted.'),
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

class _SubjectCard extends StatelessWidget {
  final Map<String, dynamic> subject;
  final VoidCallback         onEdit;
  final VoidCallback         onDelete;

  const _SubjectCard({
    required this.subject,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isLab = subject['is_lab'] == true;
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
              color       : Colors.green.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.menu_book_rounded,
              color: Colors.green,
              size : 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subject['name']?.toString() ?? '',
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
                      label: subject['code']?.toString() ?? '',
                      color: AppColors.primaryLight,
                    ),
                    const SizedBox(width: 6),
                    _Chip(
                      label: 'Year ${subject['year_of_study'] ?? 1}',
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    _Chip(
                      label: 'Sem ${subject['semester'] ?? 1}',
                      color: AppColors.textSecondary,
                    ),
                    if (isLab) ...[
                      const SizedBox(width: 6),
                      const _Chip(
                        label: 'Lab',
                        color: Colors.orange,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${subject['department_name'] ?? ''} · ${subject['course_name'] ?? ''}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
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
