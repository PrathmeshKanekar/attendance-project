import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/layout/app_layout.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/empty_state_widget.dart';
import '../../core/widgets/error_widget.dart';
import '../../core/widgets/loading_widget.dart';

// ── Providers ────────────────────────────────────────────────
final labPendingStudentsProvider =
    StateNotifierProvider<LabPendingStudentsNotifier, AsyncValue<List<Map<String, dynamic>>>>((ref) {
  return LabPendingStudentsNotifier(ref);
});

class LabPendingStudentsNotifier extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  final Ref _ref;

  LabPendingStudentsNotifier(this._ref) : super(const AsyncValue.loading()) {
    fetchPendingStudents();
  }

  Future<void> fetchPendingStudents() async {
    state = const AsyncValue.loading();
    try {
      final api = _ref.read(apiClientProvider);
      final res = await api.get('/api/lab-assistant/pending-students/');
      final list = List<Map<String, dynamic>>.from(res.data as List);
      state = AsyncValue.data(list);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  Future<void> approveStudent(BuildContext context, String studentId) async {
    try {
      final api = _ref.read(apiClientProvider);
      await api.post('/api/lab-assistant/students/$studentId/approve/');
      
      // Refresh the list
      await fetchPendingStudents();
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Student registration approved successfully.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to approve student: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> rejectStudent(BuildContext context, String studentId, String reason) async {
    try {
      final api = _ref.read(apiClientProvider);
      await api.post(
        '/api/lab-assistant/students/$studentId/reject/',
        data: {'rejection_reason': reason},
      );
      
      // Refresh the list
      await fetchPendingStudents();
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Student registration rejected.'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to reject student: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }
}

class LabAssistantApprovalsScreen extends ConsumerStatefulWidget {
  const LabAssistantApprovalsScreen({super.key});

  @override
  ConsumerState<LabAssistantApprovalsScreen> createState() => _LabAssistantApprovalsScreenState();
}

class _LabAssistantApprovalsScreenState extends ConsumerState<LabAssistantApprovalsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCourse = 'All';
  String _selectedYear = 'All';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pendingState = ref.watch(labPendingStudentsProvider);
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width > 800;

    return AppLayout(
      title: 'Student Approvals',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: () => ref.read(labPendingStudentsProvider.notifier).fetchPendingStudents(),
        ),
      ],
      child: pendingState.when(
        loading: () => const LoadingWidget(message: 'Loading pending students...'),
        error: (e, _) => AppErrorWidget(
          message: e.toString(),
          onRetry: () => ref.read(labPendingStudentsProvider.notifier).fetchPendingStudents(),
        ),
        data: (students) {
          // Dynamic filters list
          final courses = ['All', ...students.map((s) => s['course_name']?.toString() ?? '').where((c) => c.isNotEmpty).toSet()];
          final years = ['All', ...students.map((s) => s['year_of_study']?.toString() ?? '').where((y) => y.isNotEmpty).toSet()];

          // Filtering logic
          final filteredStudents = students.where((student) {
            final fullName = student['full_name']?.toString().toLowerCase() ?? '';
            final prn = student['prn']?.toString().toLowerCase() ?? '';
            final email = student['email']?.toString().toLowerCase() ?? '';
            final courseName = student['course_name']?.toString() ?? '';
            final year = student['year_of_study']?.toString() ?? '';

            final matchesSearch = fullName.contains(_searchQuery) ||
                prn.contains(_searchQuery) ||
                email.contains(_searchQuery);
            final matchesCourse = _selectedCourse == 'All' || courseName == _selectedCourse;
            final matchesYear = _selectedYear == 'All' || year == _selectedYear;

            return matchesSearch && matchesCourse && matchesYear;
          }).toList();

          if (students.isEmpty) {
            return const EmptyStateWidget(
              message: 'No pending student approvals',
              icon: Icons.check_circle_rounded,
              subtitle: 'All registered students in your college have been approved.',
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Search & Filter Panel
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: AppColors.borderColor),
                  ),
                  color: AppColors.cardBg,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: _searchController,
                                decoration: InputDecoration(
                                  hintText: 'Search by student name, PRN or email...',
                                  prefixIcon: const Icon(Icons.search_rounded),
                                  suffixIcon: _searchQuery.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear_rounded),
                                          onPressed: () {
                                            setState(() {
                                              _searchController.clear();
                                              _searchQuery = '';
                                            });
                                          },
                                        )
                                      : null,
                                ),
                                onChanged: (value) {
                                  setState(() {
                                    _searchQuery = value.toLowerCase().trim();
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: courses.contains(_selectedCourse) ? _selectedCourse : 'All',
                                decoration: const InputDecoration(
                                  labelText: 'Course',
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                items: courses.map((course) {
                                  return DropdownMenuItem<String>(
                                    value: course,
                                    child: Text(course == 'All' ? 'All Courses' : course),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  setState(() {
                                    _selectedCourse = val ?? 'All';
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: years.contains(_selectedYear) ? _selectedYear : 'All',
                                decoration: const InputDecoration(
                                  labelText: 'Year',
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                items: years.map((year) {
                                  return DropdownMenuItem<String>(
                                    value: year,
                                    child: Text(year == 'All' ? 'All Years' : 'Year $year'),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  setState(() {
                                    _selectedYear = val ?? 'All';
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Filtered count
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 4.0),
                child: Text(
                  'Found ${filteredStudents.length} pending registration(s)',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Results Table/List View
              Expanded(
                child: filteredStudents.isEmpty
                    ? const EmptyStateWidget(
                        message: 'No matching approvals found',
                        icon: Icons.search_off_rounded,
                        subtitle: 'Adjust your filters or search query.',
                      )
                    : isDesktop
                        ? _buildApprovalTable(filteredStudents)
                        : _buildApprovalCardsList(filteredStudents),
              ),
            ],
          );
        },
      ),
    );
  }

  // Mobile layout: List of cards
  Widget _buildApprovalCardsList(List<Map<String, dynamic>> students) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      itemCount: students.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final student = students[index];
        return _buildApprovalCard(student);
      },
    );
  }

  // Desktop layout: Beautiful interactive table
  Widget _buildApprovalTable(List<Map<String, dynamic>> students) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.borderColor),
        ),
        color: AppColors.cardBg,
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: DataTable(
            columnSpacing: 24,
            headingRowColor: MaterialStateProperty.all(AppColors.primaryLight.withOpacity(0.05)),
            columns: const [
              DataColumn(label: Text('Student', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('PRN', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Course / Div', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Year', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Face Registered', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Device Status', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
            ],
            rows: students.map((student) {
              final faceEnrolled = student['face_enrollment_status'] == true;
              final deviceRegistered = student['device_status'] == true;

              return DataRow(
                cells: [
                  DataCell(
                    InkWell(
                      onTap: () => _viewProfileModal(student),
                      child: Row(
                        children: [
                          _buildStudentAvatar(student['student_photo'], student['full_name'], size: 38),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                student['full_name'] ?? '',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                              ),
                              Text(student['email'] ?? '', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  DataCell(Text(student['prn'] ?? '', style: const TextStyle(fontFamily: 'monospace'))),
                  DataCell(Text('${student['course_name'] ?? 'N/A'} - Div ${student['division_name'] ?? 'N/A'}')),
                  DataCell(Text('Year ${student['year_of_study'] ?? 'N/A'}')),
                  DataCell(
                    _buildStatusChip(
                      faceEnrolled ? 'Enrolled' : 'Not Enrolled',
                      faceEnrolled ? AppColors.success : AppColors.danger,
                    ),
                  ),
                  DataCell(
                    _buildStatusChip(
                      deviceRegistered ? 'Registered' : 'No Device',
                      deviceRegistered ? AppColors.success : AppColors.warning,
                    ),
                  ),
                  DataCell(
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.check_circle_rounded, color: AppColors.success),
                          tooltip: 'Approve student',
                          onPressed: () => _confirmApprove(student),
                        ),
                        IconButton(
                          icon: const Icon(Icons.cancel_rounded, color: AppColors.danger),
                          tooltip: 'Reject student',
                          onPressed: () => _showRejectDialog(student),
                        ),
                        IconButton(
                          icon: const Icon(Icons.info_rounded, color: AppColors.primaryLight),
                          tooltip: 'View details',
                          onPressed: () => _viewProfileModal(student),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildApprovalCard(Map<String, dynamic> student) {
    final faceEnrolled = student['face_enrollment_status'] == true;
    final deviceRegistered = student['device_status'] == true;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left color bar
            Container(
              width: 5,
              decoration: const BoxDecoration(
                color: AppColors.warning,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildStudentAvatar(student['student_photo'], student['full_name'], size: 60),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                student['full_name'] ?? '',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                student['email'] ?? '',
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'PRN: ${student['prn'] ?? ''}  ·  Roll No: ${student['roll_number'] ?? ''}',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                              ),
                              Text(
                                '${student['course_name'] ?? ''} - Div ${student['division_name'] ?? ''} (Year ${student['year_of_study'] ?? ''})',
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Status row
                    Row(
                      children: [
                        _buildStatusChip(
                          faceEnrolled ? 'Face: Enrolled' : 'Face: Missing',
                          faceEnrolled ? AppColors.success : AppColors.danger,
                        ),
                        const SizedBox(width: 8),
                        _buildStatusChip(
                          deviceRegistered ? 'Device: Registered' : 'Device: Unbound',
                          deviceRegistered ? AppColors.success : AppColors.warning,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.danger,
                              side: const BorderSide(color: AppColors.danger),
                              minimumSize: const Size(0, 40),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => _showRejectDialog(student),
                            icon: const Icon(Icons.close_rounded, size: 16),
                            label: const Text('Reject'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                              minimumSize: const Size(0, 40),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => _confirmApprove(student),
                            icon: const Icon(Icons.check_rounded, size: 16),
                            label: const Text('Approve'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.info_outline_rounded, color: AppColors.primaryLight),
                          onPressed: () => _viewProfileModal(student),
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

  Widget _buildStudentAvatar(String? photoUrl, String? fullName, {double size = 48}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: photoUrl != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Image.network(
                photoUrl,
                fit: BoxFit.cover,
                errorBuilder: (c, e, s) => Center(child: Text(_initials(fullName), style: const TextStyle(fontWeight: FontWeight.bold))),
              ),
            )
          : Center(
              child: Text(
                _initials(fullName),
                style: TextStyle(color: AppColors.primaryLight, fontWeight: FontWeight.bold, fontSize: size * 0.4),
              ),
            ),
    );
  }

  Widget _buildStatusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  String _initials(String? name) {
    if (name == null || name.trim().isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  // Approve confirmation dialog
  Future<void> _confirmApprove(Map<String, dynamic> student) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve Student'),
        content: Text('Are you sure you want to approve ${student['full_name']}?\nThis will grant them login access and enable biometric attendance.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      ref.read(labPendingStudentsProvider.notifier).approveStudent(context, student['id']);
    }
  }

  // Reject dialog with optional reason
  Future<void> _showRejectDialog(Map<String, dynamic> student) async {
    final reasonCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Student Registration'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Provide a reason for rejecting ${student['full_name']}:'),
              const SizedBox(height: 12),
              TextFormField(
                controller: reasonCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'e.g. Blurry face photo, incorrect roll number...',
                  labelText: 'Rejection Reason',
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Rejection reason is required' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      ref.read(labPendingStudentsProvider.notifier).rejectStudent(
            context,
            student['id'],
            reasonCtrl.text.trim(),
          );
    }
  }

  // View full profile details modal
  void _viewProfileModal(Map<String, dynamic> student) {
    final faceEnrolled = student['face_enrollment_status'] == true;
    final deviceRegistered = student['device_status'] == true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 50,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.borderColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  _buildStudentAvatar(student['student_photo'], student['full_name'], size: 80),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          student['full_name'] ?? '',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: AppColors.textPrimary),
                        ),
                        Text(
                          student['email'] ?? '',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        _buildStatusChip(
                          'PENDING LAB APPROVAL',
                          AppColors.warning,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Divider(color: AppColors.borderColor),
              const SizedBox(height: 16),
              const Text(
                'Registration Profile Details',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 16),
              _buildDetailRow(Icons.badge_outlined, 'PRN Number', student['prn'] ?? 'N/A'),
              _buildDetailRow(Icons.pin_outlined, 'Roll Number', student['roll_number'] ?? 'N/A'),
              _buildDetailRow(Icons.school_outlined, 'Course Name', student['course_name'] ?? 'N/A'),
              _buildDetailRow(Icons.groups_outlined, 'Division Name', student['division_name'] ?? 'N/A'),
              _buildDetailRow(Icons.calendar_today_outlined, 'Year of Study', 'Year ${student['year_of_study'] ?? 'N/A'}'),
              _buildDetailRow(Icons.phone_outlined, 'Mobile Number', student['phone'] != '' ? student['phone'] : 'N/A'),
              _buildDetailRow(Icons.face_retouching_natural_outlined, 'Biometric Enrollment', faceEnrolled ? 'Registered (128-d Embedding Generated)' : 'Missing'),
              _buildDetailRow(Icons.phone_android_outlined, 'Device Linkage', deviceRegistered ? 'Registered (Bound to Hardware)' : 'No Hardware Registry Found'),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        side: const BorderSide(color: AppColors.danger),
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        _showRejectDialog(student);
                      },
                      child: const Text('Reject Registration'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        _confirmApprove(student);
                      },
                      child: const Text('Approve Student'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primaryLight, size: 20),
          const SizedBox(width: 12),
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textSecondary, fontSize: 14),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
