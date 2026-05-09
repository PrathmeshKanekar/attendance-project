class FaceScanParams {
  final String sessionId;
  final double lat;
  final double lng;
  final double altitude;
  final String deviceId;

  const FaceScanParams({
    required this.sessionId,
    required this.lat,
    required this.lng,
    required this.altitude,
    required this.deviceId,
  });
}
