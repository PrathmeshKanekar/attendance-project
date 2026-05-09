
import 'package:dartz/dartz.dart';

abstract class IAttendanceRepository {
  Future<Either<String, Map<String, dynamic>>> validateSession(String sessionId);
  Future<Either<String, Map<String, dynamic>>> validateGeoLocation({
    required double lat,
    required double lng,
    required double altitude,
    required String sessionId,
    double? accuracy,
  });
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
  });
}
