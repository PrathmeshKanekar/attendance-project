
import 'package:dartz/dartz.dart';
import '../entities/report_data.dart';

abstract class IReportRepository {
  Future<Either<String, List<ReportSummary>>> getDashboardSummary();
  Future<Either<String, List<ChartDataPoint>>> getAttendanceTrends({
    required DateTime start,
    required DateTime end,
    String? departmentId,
  });
  Future<Either<String, List<Map<String, dynamic>>>> getDetailedReport({
    required ReportType type,
    Map<String, dynamic>? filters,
  });
  Future<Either<String, String>> exportReport({
    required ReportType type,
    required String format, // pdf, excel, csv
    Map<String, dynamic>? filters,
  });
}
