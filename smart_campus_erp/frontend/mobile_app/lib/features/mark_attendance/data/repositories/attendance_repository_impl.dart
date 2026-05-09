
import 'package:dartz/dartz.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/repositories/i_attendance_repository.dart';
import 'package:dio/dio.dart';
import '../../../../core/offline/offline_attendance_service.dart';

class AttendanceRepositoryImpl implements IAttendanceRepository {
  final ApiClient _api;
  final _offlineService = OfflineAttendanceService();

  AttendanceRepositoryImpl(this._api);

  @override
  Future<Either<String, Map<String, dynamic>>> validateSession(String sessionId) async {
    try {
      final res = await _api.get('/api/attendance/sessions/$sessionId/validate/');
      return Right(Map<String, dynamic>.from(res.data));
    } catch (e) {
      return Left(e.toString());
    }
  }

  @override
  Future<Either<String, Map<String, dynamic>>> validateGeoLocation({
    required double lat,
    required double lng,
    required double altitude,
    required String sessionId,
    double? accuracy,
  }) async {
    try {
      final res = await _api.post('/api/attendance/check-location/', data: {
        'session_id': sessionId,
        'lat': lat,
        'lng': lng,
        'altitude': altitude,
        'accuracy': accuracy ?? 10.0,
      });
      return Right(Map<String, dynamic>.from(res.data));
    } catch (e) {
      return Left(e.toString());
    }
  }

  @override
  Future<Either<String, bool>> markAttendance({
    required String sessionId,
    required String faceImageBase64,
    required double lat,
    required double lng,
    required double altitude,
    required String deviceId,
    required int blinkCount,
    double? accuracy,
    Map<String, dynamic>? extraSensors,
  }) async {
    final data = {
      'session_id': sessionId,
      'lat': lat,
      'lng': lng,
      'altitude': altitude,
      'accuracy': accuracy ?? 10.0,
      'device_id': deviceId,
      'face_image_b64': faceImageBase64,
      'blink_count': blinkCount,
      if (extraSensors != null) ...extraSensors,
    };

    try {
      final res = await _api.post('/api/attendance/mark/', data: data);
      return Right(res.data['status'] == 'success');
    } catch (e) {
      // Check if it's a network error
      if (e is DioException && 
          (e.type == DioExceptionType.connectionTimeout || 
           e.type == DioExceptionType.receiveTimeout ||
           e.type == DioExceptionType.connectionError)) {
        
        // Save for later
        await _offlineService.saveForLater(data);
        return const Right(true); // Return true but we should ideally notify the user it's offline
      }
      return Left(e.toString());
    }
  }
}
