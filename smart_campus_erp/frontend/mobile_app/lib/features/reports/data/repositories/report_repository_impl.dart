
import 'package:dartz/dartz.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/entities/report_data.dart';
import '../../domain/repositories/i_report_repository.dart';

class ReportRepositoryImpl implements IReportRepository {
  final ApiClient _api;

  ReportRepositoryImpl(this._api);

  @override
  Future<Either<String, List<ReportSummary>>> getDashboardSummary() async {
    try {
      final res = await _api.get('/api/reports/summary/');
      final data = res.data as List;
      return Right(data.map((e) => ReportSummary(
        title: e['title'],
        value: e['value'],
        trend: (e['trend'] as num).toDouble(),
        isPositive: e['is_positive'],
      )).toList());
    } catch (e) {
      return Left(e.toString());
    }
  }

  @override
  Future<Either<String, List<ChartDataPoint>>> getAttendanceTrends({
    required DateTime start,
    required DateTime end,
    String? departmentId,
  }) async {
    try {
      final res = await _api.get('/api/reports/trends/', params: {
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        if (departmentId != null) 'department_id': departmentId,
      });
      
      List rawData = [];
      if (res.data is List) {
        rawData = res.data as List;
      } else if (res.data is Map && res.data['trends'] != null) {
        rawData = res.data['trends'] as List;
      }

      return Right(rawData.map((e) => ChartDataPoint(
        e['date']?.toString() ?? e['label']?.toString() ?? '',
        (e['percentage'] as num? ?? e['value'] as num? ?? 0.0).toDouble(),
      )).toList());
    } catch (e) {
      return Left(e.toString());
    }
  }

  @override
  Future<Either<String, List<Map<String, dynamic>>>> getDetailedReport({
    required ReportType type,
    Map<String, dynamic>? filters,
  }) async {
    try {
      final res = await _api.get('/api/reports/detailed/', params: {
        'type': type.name,
        ...?filters,
      });
      return Right(List<Map<String, dynamic>>.from(res.data['results'] ?? res.data));
    } catch (e) {
      return Left(e.toString());
    }
  }

  @override
  Future<Either<String, String>> exportReport({
    required ReportType type,
    required String format,
    Map<String, dynamic>? filters,
  }) async {
    try {
      final res = await _api.get('/api/reports/export/', params: {
        'type': type.name,
        'format': format,
        ...?filters,
      });
      return Right(res.data['download_url'] ?? '');
    } catch (e) {
      return Left(e.toString());
    }
  }
}
