import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_campus_app/core/network/api_client.dart';

// ─────────────────────────────────────────────────────────────────────────────
// STATES
// ─────────────────────────────────────────────────────────────────────────────
abstract class ReportsState extends Equatable {
  const ReportsState();
  @override
  List<Object?> get props => [];
}

class ReportsInitial extends ReportsState {}

class ReportsLoading extends ReportsState {}

class ReportsLoaded extends ReportsState {
  final List<Map<String, dynamic>> summaryCards;
  final List<Map<String, dynamic>> trends;
  final List<Map<String, dynamic>> detailedData;
  final String activeReportType; // 'attendance' | 'defaulters' | 'overview'
  final String? warningMessage;  // Non-fatal partial load warning

  const ReportsLoaded({
    required this.summaryCards,
    required this.trends,
    this.detailedData = const [],
    this.activeReportType = 'attendance',
    this.warningMessage,
  });

  ReportsLoaded copyWith({
    List<Map<String, dynamic>>? summaryCards,
    List<Map<String, dynamic>>? trends,
    List<Map<String, dynamic>>? detailedData,
    String? activeReportType,
    String? warningMessage,
  }) =>
      ReportsLoaded(
        summaryCards: summaryCards ?? this.summaryCards,
        trends: trends ?? this.trends,
        detailedData: detailedData ?? this.detailedData,
        activeReportType: activeReportType ?? this.activeReportType,
        warningMessage: warningMessage,
      );

  @override
  List<Object?> get props =>
      [summaryCards, trends, detailedData, activeReportType, warningMessage];
}

class ReportsError extends ReportsState {
  final String message;
  const ReportsError(this.message);
  @override
  List<Object?> get props => [message];
}

// ─────────────────────────────────────────────────────────────────────────────
// CUBIT
// ─────────────────────────────────────────────────────────────────────────────
class ReportsCubit extends Cubit<ReportsState> {
  final ApiClient _api;

  ReportsCubit(this._api) : super(ReportsInitial());

  /// Load summary cards AND trends independently.
  /// If one fails, the other still shows — no full-page error on partial failure.
  Future<void> loadDashboard() async {
    emit(ReportsLoading());

    List<Map<String, dynamic>> summaryCards = [];
    List<Map<String, dynamic>> trends = [];
    String? warning;

    // ── Summary cards ──────────────────────────────────────────────────────
    try {
      final res = await _api.get('/api/reports/summary/');
      summaryCards = _extractList(res.data, ['data', 'summaries', 'results']);
    } catch (e) {
      warning = 'Summary cards could not load: $e';
    }

    // ── Attendance trends (last 30 days) ────────────────────────────────────
    try {
      final res = await _api.get('/api/reports/trends/', params: {'days': '30'});
      trends = _extractList(res.data, ['data', 'trends', 'results']);
    } catch (e) {
      // Trends are non-critical — just empty the chart
      if (warning != null) {
        warning = '$warning\nTrends chart unavailable.';
      }
    }

    emit(ReportsLoaded(
      summaryCards: summaryCards,
      trends: trends,
      warningMessage: warning,
    ));
  }

  /// Load teacher attendance summary for a specific allocation.
  Future<void> loadAttendanceSummary({
    required String allocationId,
    required String startDate,
    required String endDate,
    double threshold = 75.0,
  }) async {
    final current = state is ReportsLoaded ? state as ReportsLoaded : null;
    emit(ReportsLoading());

    try {
      final res = await _api.get('/api/reports/attendance-summary/', params: {
        'allocation_id': allocationId,
        'start_date': startDate,
        'end_date': endDate,
        'threshold': threshold.toString(),
      });

      final raw = res.data;
      final inner = (raw is Map && raw['data'] is Map)
          ? raw['data'] as Map
          : (raw is Map ? raw : <String, dynamic>{});

      final students = (inner['students'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      emit(ReportsLoaded(
        summaryCards: current?.summaryCards ?? [],
        trends: current?.trends ?? [],
        detailedData: students,
        activeReportType: 'attendance',
      ));
    } catch (e) {
      emit(ReportsError('Failed to load attendance summary: $e'));
    }
  }

  /// Load defaulters list.
  Future<void> loadDefaulters({
    String? allocationId,
    double threshold = 75.0,
  }) async {
    final current = state is ReportsLoaded ? state as ReportsLoaded : null;
    emit(ReportsLoading());

    try {
      final params = <String, dynamic>{'threshold': threshold.toString()};
      if (allocationId != null) params['allocation_id'] = allocationId;

      final res = await _api.get('/api/reports/defaulters/', params: params);
      final raw = res.data;
      final inner = (raw is Map && raw['data'] is Map)
          ? raw['data'] as Map
          : (raw is Map ? raw : <String, dynamic>{});

      final defaulters = (inner['defaulters'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      emit(ReportsLoaded(
        summaryCards: current?.summaryCards ?? [],
        trends: current?.trends ?? [],
        detailedData: defaulters,
        activeReportType: 'defaulters',
      ));
    } catch (e) {
      emit(ReportsError('Failed to load defaulters: $e'));
    }
  }

  /// Load college overview (Principal / HOD).
  Future<void> loadCollegeOverview() async {
    emit(ReportsLoading());
    try {
      final res = await _api.get('/api/reports/college/overview/');
      final raw = res.data;
      final inner = (raw is Map && raw['data'] is Map)
          ? raw['data'] as Map
          : (raw is Map ? raw : <String, dynamic>{});

      final subjects = (inner['subjects'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      emit(ReportsLoaded(
        summaryCards: _buildOverviewCards(inner['overview'] as Map?),
        trends: [],
        detailedData: subjects,
        activeReportType: 'overview',
      ));
    } catch (e) {
      emit(ReportsError('Failed to load college overview: $e'));
    }
  }

  List<Map<String, dynamic>> _buildOverviewCards(Map? overview) {
    if (overview == null) return [];
    return [
      {'title': 'Total Subjects',   'value': '${overview['total_subjects'] ?? 0}',   'is_positive': true},
      {'title': 'Total Students',   'value': '${overview['total_students'] ?? 0}',   'is_positive': true},
      {'title': 'At Risk Students', 'value': '${overview['total_at_risk'] ?? 0}',    'is_positive': false},
      {'title': 'College Avg',      'value': '${overview['college_avg_pct'] ?? 0}%', 'is_positive': true},
    ];
  }

  List<Map<String, dynamic>> _extractList(dynamic raw, List<String> keys) {
    if (raw == null) return [];
    if (raw is List) {
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    if (raw is Map) {
      for (final k in keys) {
        final v = raw[k];
        if (v is List) {
          return v.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }
    }
    return [];
  }
}