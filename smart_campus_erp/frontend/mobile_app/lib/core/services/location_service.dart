import 'package:location/location.dart' as loc;
import 'package:geolocator/geolocator.dart';
import 'dart:async';

class LocationException implements Exception {
  final String message;
  final bool isServiceDisabled;
  final bool isPermissionDenied;
  final bool isPermissionPermanentlyDenied;

  LocationException(
    this.message, {
    this.isServiceDisabled = false,
    this.isPermissionDenied = false,
    this.isPermissionPermanentlyDenied = false,
  });

  @override
  String toString() => message;
}

class LocationService {
  final loc.Location _location = loc.Location();

  Future<Position> getCurrentPosition({
    LocationAccuracy desiredAccuracy = LocationAccuracy.bestForNavigation,
    Duration timeLimit = const Duration(seconds: 30),
  }) async {
    // 1. Check if location services are enabled.
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) {
        throw LocationException(
          'Location services are disabled. Please enable them in settings.',
          isServiceDisabled: true,
        );
      }
    }

    // 2. Check and request permissions.
    loc.PermissionStatus permissionGranted = await _location.hasPermission();
    if (permissionGranted == loc.PermissionStatus.denied) {
      permissionGranted = await _location.requestPermission();
      if (permissionGranted != loc.PermissionStatus.granted) {
        throw LocationException(
          'Location permissions are denied. We need them to verify your presence.',
          isPermissionDenied: true,
        );
      }
    }

    if (permissionGranted == loc.PermissionStatus.deniedForever) {
      throw LocationException(
        'Location permissions are permanently denied. Please enable them in app settings.',
        isPermissionPermanentlyDenied: true,
      );
    }

    // 3. Configure Location settings to map to PRIORITY_HIGH_ACCURACY (Fuses WiFi, sensors, GPS)
    await _location.changeSettings(
      accuracy: loc.LocationAccuracy.high,
      interval: 1000,
      distanceFilter: 0,
    );

    // 4. Get the current Fused position.
    try {
      final locationData = await _location.getLocation().timeout(timeLimit);
      return Position(
        longitude: locationData.longitude ?? 0.0,
        latitude: locationData.latitude ?? 0.0,
        timestamp: DateTime.now(),
        accuracy: locationData.accuracy ?? 0.0,
        altitude: locationData.altitude ?? 0.0,
        heading: locationData.heading ?? 0.0,
        speed: locationData.speed ?? 0.0,
        speedAccuracy: locationData.speedAccuracy ?? 0.0,
        altitudeAccuracy: 0.0,
        headingAccuracy: 0.0,
        floor: null,
        isMocked: false,
      );
    } catch (e) {
      throw LocationException('Failed to acquire Fused GPS lock: $e');
    }
  }

  Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
  }

  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }
}
