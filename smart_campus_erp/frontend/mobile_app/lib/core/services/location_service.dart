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
  Future<Position> getCurrentPosition() async {
    // 1. Check if location services are enabled.
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw LocationException(
        'Location services are disabled. Please enable them in settings.',
        isServiceDisabled: true,
      );
    }

    // 2. Check and request permissions.
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw LocationException(
          'Location permissions are denied. We need them to verify your presence.',
          isPermissionDenied: true,
        );
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw LocationException(
        'Location permissions are permanently denied. Please enable them in app settings.',
        isPermissionPermanentlyDenied: true,
      );
    }

    // 3. Get the current position with timeout and fallback.
    try {
      // Try to get high accuracy position first with a reasonable timeout.
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 15),
      );
    } on TimeoutException {
      // If high accuracy fails, try to get last known location or a less accurate one quickly.
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) return lastKnown;
      
      // Fallback to lower accuracy if best accuracy times out.
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (e) {
      throw LocationException('Failed to acquire GPS lock: $e');
    }
  }

  Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
  }

  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }
}
