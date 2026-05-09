import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/app_constants.dart';
import '../services/secure_storage_service.dart';

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    wOptions: WindowsOptions(),
    lOptions: LinuxOptions(),
  );
});

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient();
});

class ApiClient {
  late final Dio _dio;

  ApiClient() {
    _dio = Dio(
      BaseOptions(
        // We will override this in the interceptor to handle dynamic Base URLs
        baseUrl        : AppConstants.baseUrl,
        connectTimeout : const Duration(milliseconds: AppConstants.connectTimeoutMs),
        receiveTimeout : const Duration(milliseconds: AppConstants.receiveTimeoutMs),
        headers        : {
          'Content-Type': 'application/json',
          'Accept'      : 'application/json',
        },
      ),
    );

    _dio.interceptors.addAll([
      _BaseUrlInterceptor(),
      _AuthInterceptor(_dio),
      LogInterceptor(
        requestBody   : true,
        responseBody  : true,
        requestHeader : true,
      ),
    ]);
  }

  Dio get dio => _dio;

  Future<Response> get(String path, {Map<String, dynamic>? params}) =>
      _dio.get(path, queryParameters: params);

  Future<Response> download(
    String url,
    String savePath, {
    ProgressCallback? onReceiveProgress,
    Map<String, dynamic>? params,
  }) =>
      _dio.download(
        url,
        savePath,
        onReceiveProgress: onReceiveProgress,
        queryParameters: params,
      );

  Future<Response> post(String path, {dynamic data}) =>
      _dio.post(path, data: data);

  Future<Response> put(String path, {dynamic data}) =>
      _dio.put(path, data: data);

  Future<Response> patch(String path, {dynamic data}) =>
      _dio.patch(path, data: data);

  Future<Response> delete(String path) =>
      _dio.delete(path);
}

/// Dynamic Base URL Interceptor
class _BaseUrlInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final baseUrl = await SecureStorageService.getBaseUrl();
    options.baseUrl = baseUrl;
    handler.next(options);
  }
}

/// Authentication Interceptor
class _AuthInterceptor extends Interceptor {
  final Dio _dio;
  _AuthInterceptor(this._dio);

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
      try {
        final refresh = await SecureStorageService.getRefreshToken();
        if (refresh == null) {
          await SecureStorageService.clearAll();
          return handler.next(err);
        }

        final baseUrl = await SecureStorageService.getBaseUrl();
        final refreshDio = Dio(BaseOptions(baseUrl: baseUrl));
        
        final res = await refreshDio.post('/api/auth/refresh/', data: {'refresh': refresh});
        final newToken = res.data['access'];
        
        if (newToken != null) {
          await SecureStorageService.saveTokens(
            access: newToken,
            refresh: res.data['refresh'] ?? refresh,
          );
          
          // Retry original request
          err.requestOptions.headers['Authorization'] = 'Bearer $newToken';
          final response = await _dio.fetch(err.requestOptions);
          return handler.resolve(response);
        }
      } catch (_) {
        await SecureStorageService.clearAll();
      }
    }
    handler.next(err);
  }
}
