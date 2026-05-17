class AppConstants {
  AppConstants._();

  static const String tokenKey   = 'access_token';
  static const String refreshKey = 'refresh_token';
  static const String userKey    = 'user_data';

  static const int connectTimeoutMs = 10000;
  static const int receiveTimeoutMs = 10000;

  static const int    requiredBlinks        = 3;
  static const double faceMatchConfidence   = 60.0;
  static const double defaultGeoRadiusMeters = 30.0;
}
