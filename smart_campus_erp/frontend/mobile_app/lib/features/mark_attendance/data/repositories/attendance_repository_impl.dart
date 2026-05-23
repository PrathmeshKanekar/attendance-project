
import 'package:flutter/foundation.dart';
import 'package:dartz/dartz.dart';
import 'package:smart_campus_app/core/network/api_client.dart';
import 'package:smart_campus_app/features/mark_attendance/domain/repositories/i_attendance_repository.dart';
import 'package:dio/dio.dart';
import 'package:smart_campus_app/core/offline/offline_attendance_service.dart';

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
    bool isMocked = false,
  }) async {
    final data = {
      'session_id': sessionId,
      'lat': lat,
      'lng': lng,
      'altitude': altitude,
      'accuracy': accuracy ?? 10.0,
      'device_id': deviceId,
      'is_mocked': isMocked,
      'face_image_b64': faceImageBase64,
      'blink_count': blinkCount,
      if (extraSensors != null) ...extraSensors,
    };

    try {
      final res = await _api.post('/api/attendance/mark/', data: data);
      final rawData = res.data;
      final isSuccess = (rawData is Map) && 
          (rawData['success'] == true && rawData.containsKey('attendance_id'));
      
      if (isSuccess) {
        debugPrint("Attendance inserted successfully: $rawData");
        return const Right(true);
      } else {
        final errorMsg = (rawData is Map) ? (rawData['error'] ?? 'Attendance insert failed') : 'Invalid response from server';
        return Left(errorMsg.toString());
      }
    } catch (e) {
      // Check if it's a network error
      if (e is DioException && 
          (e.type == DioExceptionType.connectionTimeout || 
           e.type == DioExceptionType.receiveTimeout ||
           e.type == DioExceptionType.connectionError)) {
        
        // Save for later
        await _offlineService.saveForLater(data);
        return const Left('Saved offline. Attendance will sync once connection is restored.');
      }
      if (e is DioException && e.response?.data != null) {
        final errData = e.response!.data;
        if (errData is Map) {
          if (errData.containsKey('error')) {
            return Left(errData['error'].toString());
          }
          if (errData.containsKey('detail')) {
            return Left(errData['detail'].toString());
          }
          if (errData.containsKey('message')) {
            return Left(errData['message'].toString());
          }
        }
      }
      return Left(e.toString());
    }
  }

  @override
  Future<Either<String, bool>> logSecurityAlert({
    required String type,
    required double lat,
    required double lng,
    required String deviceId,
  }) async {
    try {
      final res = await _api.post('/api/attendance/security-alert/', data: {
        'type': type,
        'attempted_lat': lat,
        'attempted_lng': lng,
        'timestamp': DateTime.now().toIso8601String(),
        'device_id': deviceId,
      });
      final rawData = res.data;
      final isSuccess = (rawData is Map) && 
          (rawData['status'] == 'alert_received' || rawData['status'] == 'success' || rawData['success'] == true);
      return Right(isSuccess);
    } catch (e) {
      if (e is DioException && e.response?.data != null) {
        final data = e.response!.data;
        if (data is Map && data.containsKey('error')) {
          return Left(data['error'].toString());
        }
      }
      return Left(e.toString());
    }
  }

  @override
  Future<Either<String, Map<String, dynamic>>> registerDevice({
    required String deviceId,
    required String deviceName,
    required String platform,
  }) async {
    try {
      final res = await _api.post('/api/devices/register/', data: {
        'device_id': deviceId,
        'device_name': deviceName,
        'platform': platform,
      });
      return Right(Map<String, dynamic>.from(res.data));
    } catch (e) {
      if (e is DioException && e.response?.data != null) {
        final data = e.response!.data;
        if (data is Map && data.containsKey('error')) {
          return Left(data['error'].toString());
        }
      }
      return Left(e.toString());
    }
  }

  @override
  Future<Either<String, Map<String, dynamic>>> verifyDevice({
    required String deviceId,
  }) async {
    try {
      final res = await _api.get('/api/devices/me/', params: {
        'device_id': deviceId,
      });
      return Right(Map<String, dynamic>.from(res.data));
    } catch (e) {
      if (e is DioException && e.response?.data != null) {
        final data = e.response!.data;
        if (data is Map && data.containsKey('error')) {
          return Left(data['error'].toString());
        }
      }
      return Left(e.toString());
    }
  }

  @override
  Future<Either<String, Map<String, dynamic>>> refreshDeviceBinding({
    required String deviceId,
    required String deviceName,
    required String platform,
  }) async {
    try {
      final res = await _api.post('/api/devices/refresh/', data: {
        'device_id': deviceId,
        'device_name': deviceName,
        'platform': platform,
      });
      return Right(Map<String, dynamic>.from(res.data));
    } catch (e) {
      if (e is DioException && e.response?.data != null) {
        final data = e.response!.data;
        if (data is Map && data.containsKey('error')) {
          return Left(data['error'].toString());
        }
      }
      return Left(e.toString());
    }
  }
}
