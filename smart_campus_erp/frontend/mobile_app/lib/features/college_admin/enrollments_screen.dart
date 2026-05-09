import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../core/widgets/empty_state_widget.dart';
import 'providers/academic_providers.dart';

class EnrollmentsScreen extends ConsumerStatefulWidget {
  const EnrollmentsScreen({super.key});

  @override
  ConsumerState<EnrollmentsScreen> createState() => _EnrollmentsScreenState();
}

class _EnrollmentsScreenState extends ConsumerState<EnrollmentsScreen> {
  String? _selectedAllocationId;
  List<Map<String, dynamic>> _enrolledStudents = [];
  bool _loadingEnrolled = false;
  String? _errorEnrolled;

  Future<void> _fetchEnrolled(String allocId) async {
    setState(() {
      _loadingEnrolled = true;
      _errorEnrolled = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.get('/api/enrollments/', params: {
        'subject_allocation_id': allocId,
      });
      if (mounted) {
        setState(() {
          _enrolledStudents = List<Map<String, dynamic>>.from(res.data as List);
          _loadingEnrolled = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorEnrolled = e.toString();
          _loadingEnrolled = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final allocationsAsync = ref.watch(allocationsProvider);
    final studentsAsync = ref.watch(studentsProvider);

    return AppLayout(
      title  : 'Student Enrollments',
      actions: [
        IconButton(
          icon     : const Icon(Icons.refresh_rounded),
          onPressed: () {
            ref.invalidate(allocationsProvider);
            if (_selectedAllocationId != null) {
              _fetchEnrolled(_selectedAllocationId!);
            }
          },
          tooltip  : 'Refresh',
        ),
      ],
      fab: _selectedAllocationId != null
          ? FloatingActionButton.extended(
              onPressed: () {
                final alloc = (allocationsAsync.value ?? []).firstWhere(
                  (a) => a['id'].toString() == _selectedAllocationId,
                  orElse: () => {},
                );
                _showBulkEnrollBottomSheet(
                  context, ref,
                  alloc,
                  studentsAsync.value ?? [],
                  _enrolledStudents,
                );
              },
              icon: const Icon(Icons.group_add_rounded),
              label: const Text('Bulk Enroll Students'),
              backgroundColor: AppColors.primaryLight,
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section 1: Dropdown
            allocationsAsync.when(
              loading: () => const LoadingWidget(message: 'Loading allocations...'),
              error: (err, _) => Center(child: Text('Error loading allocations: $err')),
              data: (allocations) {
                if (allocations.isEmpty) {
                  return const EmptyStateWidget(
                    message: 'No allocations found',
                    icon: Icons.assignment_rounded,
                    subtitle: 'Please allocate a subject to a teacher first',
                  );
                }
                return DropdownButtonFormField<String>(
                  value: _selectedAllocationId,
                  hint: const Text('Select Subject Allocation'),
                  isExpanded: true,
                  items: allocations.map((a) {
                    return DropdownMenuItem<String>(
                      value: a['id'].toString(),
                      child: Text(
                        '${a['subject_name'] ?? ''} — ${a['division_name'] ?? ''} (Y${a['division_year'] ?? 1})',
                        style: const TextStyle(fontSize: 14),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedAllocationId = val);
                      _fetchEnrolled(val);
                    }
                  },
                );
              },
            ),
            const SizedBox(height: 16),
            // Section 2: Enrolled Students
            if (_selectedAllocationId == null)
              const Expanded(
                child: Center(
                  child: Text(
                    'Select a subject allocation to view enrolled students.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              )
            else if (_loadingEnrolled)
              const Expanded(
                child: Center(child: LoadingWidget(message: 'Loading enrolled students...')),
              )
            else if (_errorEnrolled != null)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Error: $_errorEnrolled', style: const TextStyle(color: AppColors.danger)),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () => _fetchEnrolled(_selectedAllocationId!),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            else if (_enrolledStudents.isEmpty)
              const Expanded(
                child: Center(
                  child: Text(
                    'No students enrolled in this allocation yet.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: _enrolledStudents.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, index) {
                    final s = _enrolledStudents[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.primaryLight.withOpacity(0.12),
                        child: const Icon(Icons.person, color: AppColors.primaryLight),
                      ),
                      title: Text(
                        s['student_name'] ?? 'Student',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('PRN: ${s['prn'] ?? 'N/A'}  •  Roll: ${s['roll_number'] ?? 'N/A'}'),
                      trailing: Text(
                        s['enrolled_at'] != null ? s['enrolled_at'].toString().split('T')[0] : '',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showBulkEnrollBottomSheet(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> allocation,
    List<Map<String, dynamic>> allStudents,
    List<Map<String, dynamic>> enrolled,
  ) {
    final Set<String> enrolledIds = enrolled.map((e) => e['student_id'].toString()).toSet();
    final Set<String> selectedIds = {};
    String search = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final filtered = allStudents.where((s) {
            // Match division/year if possible
            if (allocation['division_name'] != null && s['division_name'] != allocation['division_name']) {
              return false;
            }
            if (search.isEmpty) return true;
            final name = (s['name'] ?? '').toString().toLowerCase();
            final prn = (s['prn'] ?? '').toString().toLowerCase();
            return name.contains(search.toLowerCase()) || prn.contains(search.toLowerCase());
          }).toList();

          return Container(
            padding: EdgeInsets.only(
              left: 16, right: 16, top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Select Students to Enroll',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextFormField(
                  decoration: const InputDecoration(
                    hintText: 'Search by student name or PRN',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => search = v.trim()),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 300,
                  child: filtered.isEmpty
                      ? const Center(child: Text('No students found.'))
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (c, i) {
                            final s = filtered[i];
                            final sid = s['id'].toString();
                            final isEnrolled = enrolledIds.contains(sid);

                            return CheckboxListTile(
                              value: isEnrolled || selectedIds.contains(sid),
                              title: Text('${s['name'] ?? 'Student'} (PRN: ${s['prn'] ?? 'N/A'})'),
                              subtitle: Text('Roll No: ${s['roll_number'] ?? 'N/A'} • Div: ${s['division_name'] ?? 'N/A'}'),
                              enabled: !isEnrolled,
                              secondary: isEnrolled
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.success.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text('Enrolled', style: TextStyle(color: AppColors.success, fontSize: 11)),
                                    )
                                  : null,
                              onChanged: (v) {
                                if (v == null) return;
                                setState(() {
                                  if (v) {
                                    selectedIds.add(sid);
                                  } else {
                                    selectedIds.remove(sid);
                                  }
                                });
                              },
                            );
                          },
                        ),
                ),
                const SizedBox(height: 14),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                    backgroundColor: AppColors.primaryLight,
                  ),
                  onPressed: selectedIds.isEmpty
                      ? null
                      : () async {
                          Navigator.pop(ctx);
                          final api = ref.read(apiClientProvider);
                          try {
                            final res = await api.post('/api/enrollments/bulk/', data: {
                              'subject_allocation_id': allocation['id'],
                              'student_ids': selectedIds.toList(),
                            });
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('${res.data['enrolled_count'] ?? selectedIds.length} students enrolled.'),
                                  backgroundColor: AppColors.success,
                                ),
                              );
                              _fetchEnrolled(allocation['id']);
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error: $e'),
                                  backgroundColor: AppColors.danger,
                                ),
                              );
                            }
                          }
                        },
                  child: Text('Enroll ${selectedIds.length} Students'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
