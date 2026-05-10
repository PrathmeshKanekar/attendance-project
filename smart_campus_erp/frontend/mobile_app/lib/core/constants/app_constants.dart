class AppConstants {
  AppConstants._();

  // ── MOBILE CONNECTIVITY ──────────────────────────────────────────
  // 1. Android Emulator: Use http://10.0.2.2:8000
  // 2. Local Machine  : Use http://127.0.0.1:8000
  // 3. Physical Device: Use http://YOUR_PC_IP:8000 (e.g. http://192.168.x.x:8000)
  // ─────────────────────────────────────────────────────────────────
  
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.223.81.98:8000', // PC LAN IP for physical device connection
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
