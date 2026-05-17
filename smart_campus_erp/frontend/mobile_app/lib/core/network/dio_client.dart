import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api_config.dart';
import '../services/secure_storage_service.dart';
import '../constants/app_constants.dart';

final dioClientProvider = Provider<DioClient>((ref) {
  return DioClient();
});

class DioClient {
  late final Dio _dio;

  DioClient() {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(milliseconds: AppConstants.connectTimeoutMs),
        receiveTimeout: const Duration(milliseconds: AppConstants.receiveTimeoutMs),
        sendTimeout:    const Duration(milliseconds: AppConstants.receiveTimeoutMs),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    _dio.interceptors.addAll([
      _ApiBaseUrlInterceptor(),
      _ApiAuthInterceptor(_dio),
      LogInterceptor(
        requestBody: true,
        responseBody: true,
        requestHeader: true,
      ),
    ]);
  }

  Dio get instance => _dio;

  // Convenience methods
  Future<Response> get(String path, {Map<String, dynamic>? params}) =>
      _dio.get(path, queryParameters: params);

  Future<Response> post(String path, {dynamic data}) =>
      _dio.post(path, data: data);

  Future<Response> put(String path, {dynamic data}) =>
      _dio.put(path, data: data);

  Future<Response> patch(String path, {dynamic data}) =>
      _dio.patch(path, data: data);

  Future<Response> delete(String path) =>
      _dio.delete(path);

  Future<Response> download(String urlPath, dynamic savePath, {ProgressCallback? onReceiveProgress, Map<String, dynamic>? queryParameters, Options? options}) =>
      _dio.download(urlPath, savePath, onReceiveProgress: onReceiveProgress, queryParameters: queryParameters, options: options);
}

class _ApiBaseUrlInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    // Force use the centralized sanitized base URL on every request
    final baseUrl = await ApiConfig.baseUrl;
    print('DioClient: Requesting ${options.path} with BaseURL: $baseUrl');
    options.baseUrl = baseUrl;
    handler.next(options);
  }
}

class _ApiAuthInterceptor extends Interceptor {
  final Dio _dio;
  _ApiAuthInterceptor(this._dio);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await SecureStorageService.getAccessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      final refresh = await SecureStorageService.getRefreshToken();
      if (refresh != null) {
        try {
          // Use centralized config for refresh URL
          final baseUrl = await ApiConfig.baseUrl;
          final refreshDio = Dio(BaseOptions(baseUrl: baseUrl));
          
          final res = await refreshDio.post(ApiConfig.refreshToken, data: {'refresh': refresh});
          final newToken = res.data['access'];
          
          if (newToken != null) {
            await SecureStorageService.saveTokens(
              access: newToken,
              refresh: res.data['refresh'] ?? refresh,
            );
            
            err.requestOptions.headers['Authorization'] = 'Bearer $newToken';
            final response = await _dio.fetch(err.requestOptions);
            return handler.resolve(response);
          }
        } catch (e) {
          await SecureStorageService.clearAll();
        }
      }
    }
    handler.next(err);
  }
}
