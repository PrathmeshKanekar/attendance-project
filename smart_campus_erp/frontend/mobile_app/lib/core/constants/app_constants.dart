class AppConstants {
  AppConstants._();

  // Current Machine IP: 10.123.167.98
  // Use 10.0.2.2:8000 for Android Emulator
  // Use 127.0.0.1:8000 for local Windows dev
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  static const String tokenKey   = 'access_token';
  static const String refreshKey = 'refresh_token';
  static const String userKey    = 'user_data';

  static const int connectTimeoutMs = 15000;
  static const int receiveTimeoutMs = 15000;

  static const int    requiredBlinks        = 3;
  static const double faceMatchConfidence   = 60.0;
  static const double defaultGeoRadiusMeters = 30.0;
}
