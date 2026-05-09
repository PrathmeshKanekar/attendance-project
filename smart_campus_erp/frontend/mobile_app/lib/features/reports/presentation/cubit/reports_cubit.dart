
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/report_data.dart';
import '../../domain/repositories/i_report_repository.dart';

abstract class ReportsState extends Equatable {
  const ReportsState();
  @override
  List<Object?> get props => [];
}

class ReportsInitial extends ReportsState {}
class ReportsLoading extends ReportsState {}
class ReportsLoaded extends ReportsState {
  final List<ReportSummary> summaries;
  final List<ChartDataPoint> trends;
  final List<Map<String, dynamic>> detailedData;
  final ReportType activeType;

  const ReportsLoaded({
    required this.summaries,
    required this.trends,
    required this.detailedData,
    this.activeType = ReportType.attendance,
  });

  @override
  List<Object?> get props => [summaries, trends, detailedData, activeType];
}
class ReportsError extends ReportsState {
  final String message;
  const ReportsError(this.message);
  @override
  List<Object?> get props => [message];
}

class ReportsCubit extends Cubit<ReportsState> {
  final IReportRepository _repository;

  ReportsCubit(this._repository) : super(ReportsInitial());

  Future<void> loadDashboard() async {
    emit(ReportsLoading());
    
    final summaryRes = await _repository.getDashboardSummary();
    final trendsRes = await _repository.getAttendanceTrends(
      start: DateTime.now().subtract(const Duration(days: 7)),
      end: DateTime.now(),
    );

    summaryRes.fold(
      (err) => emit(ReportsError(err)),
      (summaries) {
        trendsRes.fold(
          (err) => emit(ReportsError(err)),
          (trends) => emit(ReportsLoaded(
            summaries: summaries,
            trends: trends,
            detailedData: const [],
          )),
        );
      },
    );
  }

  Future<void> loadDetailedReport(ReportType type, {Map<String, dynamic>? filters}) async {
    if (state is! ReportsLoaded) return;
    final currentState = state as ReportsLoaded;
    
    emit(ReportsLoading());
    final res = await _repository.getDetailedReport(type: type, filters: filters);
    
    res.fold(
      (err) => emit(ReportsError(err)),
      (data) => emit(ReportsLoaded(
        summaries: currentState.summaries,
        trends: currentState.trends,
        detailedData: data,
        activeType: type,
      )),
    );
  }
}
