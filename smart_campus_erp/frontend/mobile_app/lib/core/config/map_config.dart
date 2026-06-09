class MapConfig {
  /// The active tile provider. Options: 'maptiler', 'stadia', 'thunderforest', or 'osm_safe'.
  static const String provider = 'osm_safe'; // Standard OSM with safe custom headers & user agent

  /// API keys for paid/restricted tile providers
  static const String maptilerKey = '';
  static const String stadiaKey = '';
  static const String thunderforestKey = '';

  /// Dynamically resolves the URL Template based on the selected provider
  static String get urlTemplate {
    switch (provider) {
      case 'maptiler':
        final key = maptilerKey.isNotEmpty ? maptilerKey : 'oXoFp07pD9lHwJjNfW0q'; // Safe default demo key
        return 'https://api.maptiler.com/maps/streets-v2/256/{z}/{x}/{y}.png?key=$key';
      case 'stadia':
        return 'https://tiles.stadiamaps.com/tiles/alidade_smooth/{z}/{x}/{y}{r}.png${stadiaKey.isNotEmpty ? "?api_key=$stadiaKey" : ""}';
      case 'thunderforest':
        return 'https://{s}.tile.thunderforest.com/spinal-map/{z}/{x}/{y}.png?apikey=$thunderforestKey';
      case 'osm_safe':
      default:
        // standard OSM with custom User-Agent and headers
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    }
  }

  /// Dynamic subdomains
  static List<String> get subdomains {
    if (provider == 'thunderforest') {
      return const ['a', 'b', 'c'];
    }
    return const [];
  }

  /// Custom request headers to prevent 403 access blocks from public OSM endpoints
  static Map<String, String> get headers {
    return const {
      'User-Agent': 'SmartCampusERP/1.0 (com.smartcampus.app; support@smartcampus.edu)',
      'Accept': 'image/webp,image/apng,image/*,*/*;q=0.8',
    };
  }

  /// User agent package identification
  static String get userAgentPackageName => 'com.smartcampus.app';
}
