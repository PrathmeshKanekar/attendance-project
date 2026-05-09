import 'package:geolocator/geolocator.dart';

class LocationService {
  Future<Map<String, double>> getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) throw Exception('Location services disabled');
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) throw Exception('Location permission denied');
    }
    if (perm == LocationPermission.deniedForever) throw Exception('Location permission permanently denied');
    final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    return {'lat': pos.latitude, 'lng': pos.longitude, 'altitude': pos.altitude};
  }
}
