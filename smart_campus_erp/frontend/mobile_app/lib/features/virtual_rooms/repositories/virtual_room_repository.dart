import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/api_client.dart';
import '../models/virtual_room_model.dart';

class VirtualRoomRepository {
  final ApiClient _api;

  VirtualRoomRepository(this._api);

  Future<Either<String, List<VirtualRoomModel>>> getRooms() async {
    try {
      final res = await _api.get('/api/virtual-rooms/');
      final data = res.data;
      if (data is List) {
        return Right(data
            .map((e) => VirtualRoomModel.fromJson(e as Map<String, dynamic>))
            .toList());
      } else if (data is Map && data.containsKey('results') && data['results'] is List) {
        final list = data['results'] as List;
        return Right(list
            .map((e) => VirtualRoomModel.fromJson(e as Map<String, dynamic>))
            .toList());
      }
      return const Right([]);
    } on DioException catch (e) {
      return Left(_extractError(e));
    } catch (e) {
      return Left(e.toString());
    }
  }

  Future<Either<String, VirtualRoomModel>> getRoomById(String id) async {
    try {
      final res = await _api.get('/api/virtual-rooms/$id/');
      return Right(VirtualRoomModel.fromJson(res.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Left(_extractError(e));
    } catch (e) {
      return Left(e.toString());
    }
  }

  Future<Either<String, VirtualRoomModel>> createRoom(Map<String, dynamic> data) async {
    try {
      final res = await _api.post('/api/virtual-rooms/', data: data);
      return Right(VirtualRoomModel.fromJson(res.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Left(_extractError(e));
    } catch (e) {
      return Left(e.toString());
    }
  }

  Future<Either<String, VirtualRoomModel>> updateRoom(String id, Map<String, dynamic> data) async {
    try {
      final res = await _api.put('/api/virtual-rooms/$id/', data: data);
      return Right(VirtualRoomModel.fromJson(res.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Left(_extractError(e));
    } catch (e) {
      return Left(e.toString());
    }
  }

  Future<Either<String, void>> deleteRoom(String id) async {
    try {
      await _api.delete('/api/virtual-rooms/$id/');
      return const Right(null);
    } on DioException catch (e) {
      return Left(_extractError(e));
    } catch (e) {
      return Left(e.toString());
    }
  }

  String _extractError(DioException e) {
    // Handle connection-level errors first (not HTTP errors)
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Server took too long to respond. Check if the backend server is running at the configured IP.';
    }
    if (e.type == DioExceptionType.connectionError) {
      return 'Cannot connect to server. Ensure your phone and server are on the same WiFi network and the IP in ApiConfig is correct (current PC IP: ${ApiConfig.pcWifiIp}).';
    }

    final responseData = e.response?.data;
    if (responseData is Map) {
      if (responseData.containsKey('error')) {
        return responseData['error'].toString();
      }
      if (responseData.containsKey('detail')) {
        return responseData['detail'].toString();
      }
      // Collect all validation errors if present
      final buffer = StringBuffer();
      responseData.forEach((key, value) {
        if (value is List) {
          buffer.write('$key: ${value.join(", ")}\n');
        } else {
          buffer.write('$key: $value\n');
        }
      });
      if (buffer.isNotEmpty) {
        return buffer.toString().trim();
      }
    }
    return e.message ?? 'An unexpected network error occurred.';
  }
}
