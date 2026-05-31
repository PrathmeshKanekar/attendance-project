
import 'package:dartz/dartz.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/entities/report_data.dart';
import '../../domain/repositories/i_report_repository.dart';

class ReportRepositoryImpl implements IReportRepository {
  final ApiClient _api;

  ReportRepositoryImpl(this._api);

  List<dynamic> _safeExtractList(dynamic data, {List<String> keys = const ['data', 'results', 'reports', 'summaries']}) {
    if (data == null) return [];
    if (data is List) return data;
    if (data is Map) {
      for (final key in keys) {
        if (data[key] is List) {
          return data[key] as List;
        }
      }
    }
    return [];
  }

  @override
  Future<Either<String, List<ReportSummary>>> getDashboardSummary() async {
    try {
      final res = await _api.get('/api/reports/summary/');
      final data = _safeExtractList(res.data);
      return Right(data.map((e) {
        if (e is! Map) return null;
        return ReportSummary(
          title: e['title']?.toString() ?? '',
          value: e['value']?.toString() ?? '',
          trend: (e['trend'] as num? ?? 0.0).toDouble(),
          isPositive: e['is_positive'] as bool? ?? false,
        );
      }).whereType<ReportSummary>().toList());
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
      
      final data = _safeExtractList(res.data, keys: const ['trends', 'data', 'results']);
      return Right(data.map((e) {
        if (e is! Map) return null;
        return ChartDataPoint(
          e['date']?.toString() ?? e['label']?.toString() ?? '',
          (e['percentage'] as num? ?? e['value'] as num? ?? 0.0).toDouble(),
        );
      }).whereType<ChartDataPoint>().toList());
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
      final data = _safeExtractList(res.data, keys: const ['results', 'data', 'reports']);
      return Right(data.map((e) {
        if (e is Map) {
          return Map<String, dynamic>.from(e);
        }
        return <String, dynamic>{};
      }).where((element) => element.isNotEmpty).toList());
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
      if (res.data is Map) {
        return Right(res.data['download_url']?.toString() ?? res.data['data']?['download_url']?.toString() ?? '');
      }
      return Right('');
    } catch (e) {
      return Left(e.toString());
    }
  }
}

