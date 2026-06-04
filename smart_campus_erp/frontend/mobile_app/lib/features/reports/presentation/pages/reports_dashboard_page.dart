import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:smart_campus_app/core/constants/app_colors.dart';
import 'package:smart_campus_app/core/network/api_client.dart';
import 'package:smart_campus_app/core/providers/auth_provider.dart';
import 'package:smart_campus_app/core/layout/app_layout.dart';
import '../cubit/reports_cubit.dart';
import '../report_providers.dart';
import '../widgets/attendance_line_chart.dart';
import '../../domain/entities/report_data.dart';

class ReportsDashboardPage extends ConsumerStatefulWidget {
  const ReportsDashboardPage({super.key});

  @override
  ConsumerState<ReportsDashboardPage> createState() => _ReportsDashboardPageState();
}

class _ReportsDashboardPageState extends ConsumerState<ReportsDashboardPage> {
  // Advanced filter states
  String? selectedAcademicYear;
  String? selectedDepartment;
  String? selectedCourse;
  String? selectedDivision;
  String? selectedSubject;
  String? selectedAllocation;
  String? selectedFaculty;
  String? selectedSemester;
  String? selectedYearOfStudy;
  String? selectedLectureLab;
  String? selectedAttendanceStatus;
  DateTime? selectedStartDate;
  DateTime? selectedEndDate;
  DateTime? selectedSingleDate;
  String? selectedMonth;
  String? selectedYear;
  int currentPage = 1;
  bool isDownloading = false;

  final TextEditingController searchController = TextEditingController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    // Default date range of last 30 days
    selectedStartDate = DateTime.now().subtract(const Duration(days: 30));
    selectedEndDate = DateTime.now();
    
    // Initial fetch of reports
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyFilters();
    });
  }

  Map<String, dynamic> _buildQueryParams() {
    final queryParams = <String, dynamic>{};
    if (selectedAllocation != null) queryParams['allocation_id'] = selectedAllocation;
    if (selectedDepartment != null) queryParams['department_id'] = selectedDepartment;
    if (selectedCourse != null) queryParams['course_id'] = selectedCourse;
    if (selectedDivision != null) queryParams['division_id'] = selectedDivision;
    if (selectedSubject != null) queryParams['subject_id'] = selectedSubject;
    if (selectedFaculty != null) queryParams['teacher_id'] = selectedFaculty;
    if (selectedAcademicYear != null) queryParams['academic_year_id'] = selectedAcademicYear;
    if (selectedSemester != null) queryParams['semester'] = selectedSemester;
    if (selectedYearOfStudy != null) queryParams['year_of_study'] = selectedYearOfStudy;
    if (selectedLectureLab != null) {
      queryParams['is_lab'] = selectedLectureLab == 'Lab' ? 'true' : 'false';
    }
    if (selectedAttendanceStatus != null) {
      queryParams['attendance_status'] = selectedAttendanceStatus;
    }
    if (searchController.text.isNotEmpty) {
      queryParams['search'] = searchController.text;
    }
    
    if (selectedSingleDate != null) {
      queryParams['single_date'] = DateFormat('yyyy-MM-dd').format(selectedSingleDate!);
    } else if (selectedMonth != null && selectedYear != null) {
      queryParams['month'] = selectedMonth;
      queryParams['year'] = selectedYear;
    } else {
      if (selectedStartDate != null) {
        queryParams['start_date'] = DateFormat('yyyy-MM-dd').format(selectedStartDate!);
      }
      if (selectedEndDate != null) {
        queryParams['end_date'] = DateFormat('yyyy-MM-dd').format(selectedEndDate!);
      }
    }
    
    queryParams['page'] = currentPage.toString();
    queryParams['page_size'] = '20';
    
    return queryParams;
  }

  void _applyFilters() {
    final cubit = context.read<ReportsCubit>();
    cubit.loadAttendanceSummary(queryParams: _buildQueryParams());
  }

  void _resetFilters() {
    setState(() {
      selectedAcademicYear = null;
      selectedDepartment = null;
      selectedCourse = null;
      selectedDivision = null;
      selectedSubject = null;
      selectedAllocation = null;
      selectedFaculty = null;
      selectedSemester = null;
      selectedYearOfStudy = null;
      selectedLectureLab = null;
      selectedAttendanceStatus = null;
      selectedSingleDate = null;
      selectedMonth = null;
      selectedYear = null;
      selectedStartDate = DateTime.now().subtract(const Duration(days: 30));
      selectedEndDate = DateTime.now();
      currentPage = 1;
      searchController.clear();
    });
    _applyFilters();
  }

  Future<void> _exportReport(String type) async {
    setState(() => isDownloading = true);
    try {
      final api = ref.read(apiClientProvider);
      final endpoint = type == 'pdf' ? '/api/reports/download/pdf/' : '/api/reports/download/excel/';
      final queryParams = _buildQueryParams();

      Directory? dir;
      if (Platform.isAndroid) {
        dir = Directory('/storage/emulated/0/Download');
        if (!await dir.exists()) dir = await getExternalStorageDirectory();
      } else {
        dir = await getApplicationDocumentsDirectory();
      }

      final extension = type == 'pdf' ? 'pdf' : 'xlsx';
      final fileName = 'attendance_report_${DateTime.now().millisecondsSinceEpoch}.$extension';
      final savePath = '${dir!.path}/$fileName';

      await api.download(
        endpoint,
        savePath,
        queryParameters: queryParams,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${type.toUpperCase()} report exported successfully'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.success,
            action: SnackBarAction(
              label: 'OPEN',
              textColor: Colors.white,
              onPressed: () => OpenFilex.open(savePath),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final user = authState is AuthSuccess ? authState.user : null;

    return AppLayout(
      scaffoldKey: _scaffoldKey,
      endDrawer: _buildFilterDrawer(user?.role),
      title: 'Attendance Analytics',
      actions: [
        IconButton(
          icon: const Icon(Icons.tune_rounded, color: AppColors.primary),
          tooltip: 'Advanced Filters',
          onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
        ),
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
          tooltip: 'Refresh Workspace',
          onPressed: _applyFilters,
        ),
      ],
      child: BlocBuilder<ReportsCubit, ReportsState>(
        builder: (context, state) {
          if (state is ReportsLoading) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(strokeWidth: 3),
                  SizedBox(height: 16),
                  Text(
                    'Synthesizing analytical metrics...',
                    style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            );
          }

          if (state is ReportsError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 64),
                    const SizedBox(height: 16),
                    Text(
                      state.message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _applyFilters,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Reload Workspace'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (state is ReportsLoaded) {
            return _buildContent(state, user?.role);
          }

          return const SizedBox();
        },
      ),
    );
  }

  Widget _buildContent(ReportsLoaded state, String? role) {
    final meta = state.summaryMeta;
    final totalStudents = meta['total_students'] ?? 0;
    final absentCount = meta['absent_count'] ?? 0;
    final lateCount = meta['late_count'] ?? 0;
    final avgPct = meta['average_percentage'] ?? 0.0;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Analytics Action Toolbar ───────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Key Performance Indicators',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              if (isDownloading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                )
              else
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => _exportReport('pdf'),
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 16, color: AppColors.danger),
                      label: const Text('PDF', style: TextStyle(fontSize: 12, color: AppColors.danger)),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => _exportReport('excel'),
                      icon: const Icon(Icons.table_view_outlined, size: 16, color: AppColors.success),
                      label: const Text('Excel', style: TextStyle(fontSize: 12, color: AppColors.success)),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),

          // ── KPI Analytics Grid Cards ───────────────────────────────
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.4,
            children: [
              _buildMetricCard('Total Cohort', totalStudents.toString(), Icons.people_rounded, Colors.blue),
              _buildMetricCard('Average Attendance', '$avgPct%', Icons.insights_rounded, avgPct >= 75 ? Colors.green : Colors.orange),
              _buildMetricCard('Absenteeism', absentCount.toString(), Icons.cancel_outlined, Colors.red),
              _buildMetricCard('Lateness Tracked', lateCount.toString(), Icons.alarm_rounded, Colors.amber),
            ],
          ),
          const SizedBox(height: 24),

          // ── Interactive Trends Chart ───────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Historical Trends', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: const Text('Reactive Analysis', style: TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (state.trends.isNotEmpty)
            AttendanceLineChart(
              data: state.trends
                  .map((e) => ChartDataPoint(
                        e['date']?.toString() ?? '',
                        (e['percentage'] as num? ?? 0.0).toDouble(),
                      ))
                  .toList(),
            )
          else
            _buildEmptySection(Icons.show_chart_rounded, 'Aggregate trend lines are synthesizing.'),
          const SizedBox(height: 24),

          // ── Professional Data Table ───────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Cohort Roster Matrix', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text('$totalStudents records captured', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 12),
          if (state.detailedData.isNotEmpty) ...[
            _buildResponsiveTable(state.detailedData),
            const SizedBox(height: 16),
            _buildPaginationControls(state.pagination),
          ] else
            _buildEmptySection(Icons.dataset_rounded, 'Cohort Roster matches no active records.'),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderColor),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 20),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: AppColors.textSecondary),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text(title, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResponsiveTable(List<Map<String, dynamic>> records) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 24,
          headingRowColor: MaterialStateProperty.all(AppColors.bgSecondary.withOpacity(0.3)),
          columns: const [
            DataColumn(label: Text('Roll No', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Student Name', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('PRN', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Check-in', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Present / Total', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Attendance %', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Status Tag', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          rows: records.map((r) {
            final pct = (r['percentage'] as num? ?? 0.0).toDouble();
            final isAtRisk = r['is_at_risk'] as bool? ?? false;
            final isDaily = selectedSingleDate != null;
            final statusStr = isDaily ? (r['status']?.toString() ?? 'absent') : (isAtRisk ? 'at risk' : 'safe');
            
            Color statusColor = Colors.green;
            if (statusStr == 'absent' || statusStr == 'at risk') statusColor = Colors.red;
            if (statusStr == 'late') statusColor = Colors.amber;
            if (statusStr == 'manual') statusColor = Colors.purple;

            return DataRow(
              cells: [
                DataCell(Text(r['roll_number']?.toString() ?? '-', style: const TextStyle(fontWeight: FontWeight.w500))),
                DataCell(
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: AppColors.primary.withOpacity(0.1),
                        child: Text(
                          r['student_name']?.toString().substring(0, 1).toUpperCase() ?? 'S',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primary),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(r['student_name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                DataCell(Text(r['prn']?.toString() ?? '-')),
                DataCell(Text(r['check_in_time']?.toString() ?? '-')),
                DataCell(Text(isDaily ? '1 / 1' : '${r['present']} / ${r['total_sessions']}')),
                DataCell(
                  Text(
                    isDaily ? (r['status'] == 'absent' ? '0.0%' : '100.0%') : '${pct.toStringAsFixed(1)}%',
                    style: TextStyle(fontWeight: FontWeight.bold, color: isAtRisk ? Colors.red : Colors.green),
                  ),
                ),
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                    child: Text(
                      statusStr.toUpperCase(),
                      style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildPaginationControls(Map<String, dynamic> pagination) {
    final page = pagination['page'] ?? 1;
    final totalPages = pagination['total_pages'] ?? 1;
    final totalCount = pagination['total_count'] ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Showing page $page of $totalPages · $totalCount records',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
                onPressed: page > 1
                    ? () {
                        setState(() => currentPage--);
                        _applyFilters();
                      }
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                onPressed: page < totalPages
                    ? () {
                        setState(() => currentPage++);
                        _applyFilters();
                      }
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptySection(IconData icon, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: Column(
        children: [
          Icon(icon, size: 48, color: AppColors.textSecondary.withOpacity(0.5)),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDrawer(String? role) {
    // Dynamic lists watched from Riverpod Providers
    final academicYears = ref.watch(academicYearsProvider).value ?? [];
    final departments = ref.watch(departmentsProvider).value ?? [];
    final courses = ref.watch(coursesProvider).value ?? [];
    final divisions = ref.watch(divisionsProvider).value ?? [];
    final subjects = ref.watch(subjectsProvider).value ?? [];
    final allocations = ref.watch(myAllocationsProvider).value ?? [];

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Drawer Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Workspace Filters', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Filter fields
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Text Search
                  const Text('Student Search', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: 'Search roll number, PRN, name...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Allocation Selector (Teachers)
                  if (role == 'teacher') ...[
                    const Text('Subject Allocation', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    _buildDropdown(
                      value: selectedAllocation,
                      items: allocations.map((e) => DropdownMenuItem<String>(
                            value: e['id'].toString(),
                            child: Text('${e['subject']['name']} (${e['division']['name']})'),
                          )).toList(),
                      onChanged: (val) => setState(() => selectedAllocation = val),
                      hint: 'Select allocated subject',
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Executive Admin Filters
                  if (role != 'teacher' && role != 'student') ...[
                    const Text('Academic Year', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    _buildDropdown(
                      value: selectedAcademicYear,
                      items: academicYears.map((e) => DropdownMenuItem<String>(
                            value: e['id'].toString(),
                            child: Text(e['name'].toString()),
                          )).toList(),
                      onChanged: (val) => setState(() => selectedAcademicYear = val),
                      hint: 'All Academic Years',
                    ),
                    const SizedBox(height: 20),

                    const Text('Department', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    _buildDropdown(
                      value: selectedDepartment,
                      items: departments.map((e) => DropdownMenuItem<String>(
                            value: e['id'].toString(),
                            child: Text(e['name'].toString()),
                          )).toList(),
                      onChanged: (val) => setState(() => selectedDepartment = val),
                      hint: 'All Departments',
                    ),
                    const SizedBox(height: 20),

                    const Text('Academic Course', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    _buildDropdown(
                      value: selectedCourse,
                      items: courses.map((e) => DropdownMenuItem<String>(
                            value: e['id'].toString(),
                            child: Text(e['name'].toString()),
                          )).toList(),
                      onChanged: (val) => setState(() => selectedCourse = val),
                      hint: 'All Courses',
                    ),
                    const SizedBox(height: 20),

                    const Text('Class Division', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    _buildDropdown(
                      value: selectedDivision,
                      items: divisions.map((e) => DropdownMenuItem<String>(
                            value: e['id'].toString(),
                            child: Text('${e['course']['code']} - ${e['name']}'),
                          )).toList(),
                      onChanged: (val) => setState(() => selectedDivision = val),
                      hint: 'All Divisions',
                    ),
                    const SizedBox(height: 20),

                    const Text('Subject Filter', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    _buildDropdown(
                      value: selectedSubject,
                      items: subjects.map((e) => DropdownMenuItem<String>(
                            value: e['id'].toString(),
                            child: Text(e['name'].toString()),
                          )).toList(),
                      onChanged: (val) => setState(() => selectedSubject = val),
                      hint: 'All Subjects',
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Semester / Lecture Type
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Semester', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 8),
                            _buildDropdown(
                              value: selectedSemester,
                              items: ['1', '2', '3', '4', '5', '6', '7', '8'].map((e) => DropdownMenuItem<String>(
                                    value: e,
                                    child: Text('Semester $e'),
                                  )).toList(),
                              onChanged: (val) => setState(() => selectedSemester = val),
                              hint: 'Select Sem',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Session Type', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 8),
                            _buildDropdown(
                              value: selectedLectureLab,
                              items: ['Lecture', 'Lab'].map((e) => DropdownMenuItem<String>(
                                    value: e,
                                    child: Text(e),
                                  )).toList(),
                              onChanged: (val) => setState(() => selectedLectureLab = val),
                              hint: 'All Types',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Lateness / Defaulters filter
                  const Text('Attendance Status Filter', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  _buildDropdown(
                    value: selectedAttendanceStatus,
                    items: const [
                      DropdownMenuItem(value: 'at_risk', child: Text('Below Threshold (<75%)')),
                      DropdownMenuItem(value: 'safe', child: Text('Above Threshold (>=75%)')),
                      DropdownMenuItem(value: 'low', child: Text('Severe Risk (<60%)')),
                    ],
                    onChanged: (val) => setState(() => selectedAttendanceStatus = val),
                    hint: 'All Statuses',
                  ),
                  const SizedBox(height: 20),

                  // Dates controls
                  const Text('Date Filtering Mode', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  ListTile(
                    title: Text(
                      selectedSingleDate != null
                          ? 'Single Date: ${DateFormat('yyyy-MM-dd').format(selectedSingleDate!)}'
                          : 'Mode: Date Range Selection',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    trailing: const Icon(Icons.calendar_month_rounded, color: AppColors.primary),
                    tileColor: AppColors.bgSecondary.withOpacity(0.3),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() {
                          selectedSingleDate = picked;
                          selectedMonth = null;
                          selectedYear = null;
                        });
                      }
                    },
                  ),
                  if (selectedSingleDate != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextButton.icon(
                        onPressed: () => setState(() => selectedSingleDate = null),
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        label: const Text('Switch back to Date Range'),
                      ),
                    ),
                  const SizedBox(height: 20),

                  // Start and End dates if single date not chosen
                  if (selectedSingleDate == null) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Start Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textSecondary)),
                              const SizedBox(height: 6),
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: selectedStartDate ?? DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime.now(),
                                  );
                                  if (picked != null) setState(() => selectedStartDate = picked);
                                },
                                child: Text(
                                  selectedStartDate != null ? DateFormat('yyyy-MM-dd').format(selectedStartDate!) : 'Pick Date',
                                  style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('End Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textSecondary)),
                              const SizedBox(height: 6),
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: selectedEndDate ?? DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime.now(),
                                  );
                                  if (picked != null) setState(() => selectedEndDate = picked);
                                },
                                child: Text(
                                  selectedEndDate != null ? DateFormat('yyyy-MM-dd').format(selectedEndDate!) : 'Pick Date',
                                  style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ],
              ),
            ),

            // Drawer Footer Action
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _resetFilters,
                      child: const Text('Reset'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        setState(() => currentPage = 1);
                        _applyFilters();
                        Navigator.pop(context);
                      },
                      child: const Text('Apply Filters'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
    required String hint,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          items: items,
          onChanged: onChanged,
          isExpanded: true,
          hint: Text(hint, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ),
      ),
    );
  }
}