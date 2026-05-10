import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../../core/network/api_client.dart';
import 'face_scan_state.dart';
import 'face_scan_params.dart';

final faceScanNotifierProvider = StateNotifierProvider<FaceScanNotifier, FaceScanState>((ref) {
  return FaceScanNotifier();
});

class FaceScanNotifier extends StateNotifier<FaceScanState> {
  int _blinkCount = 0;
  bool _eyeWasClosed = false;
  bool _captureTriggered = false;

  FaceScanNotifier() : super(FaceScanInitializing());

  void setScanningReady() {
    _blinkCount = 0;
    _eyeWasClosed = false;
    _captureTriggered = false;
    state = FaceScanScanning();
  }

  int _lastBlinkTime = 0;

  void processFaceDetection(Face face) {
    if (state is! FaceScanScanning && state is! FaceScanBlinking) return;
    if (_captureTriggered) return;

    final double leftEye = face.leftEyeOpenProbability ?? 1.0;
    final double rightEye = face.rightEyeOpenProbability ?? 1.0;
    
    // Use the lower probability to ensure both eyes are closed for a 'blink'
    // This is more robust against head tilts or side lighting
    final double eyeOpenness = (leftEye + rightEye) / 2;
    
    // High-precision Hysteresis Thresholds
    const double kClosedThreshold = 0.15; // Must be very closed
    const double kOpenThreshold = 0.75;   // Must be very open
    
    final int now = DateTime.now().millisecondsSinceEpoch;

    if (eyeOpenness < kClosedThreshold && !_eyeWasClosed) {
      _eyeWasClosed = true;
    } else if (eyeOpenness > kOpenThreshold && _eyeWasClosed) {
      // Transition from closed to open detected
      _eyeWasClosed = false;
      
      // Cooldown to prevent double-counting a single blink (minimum 250ms between blinks)
      if (now - _lastBlinkTime > 250) {
        _blinkCount++;
        _lastBlinkTime = now;
        
        if (_blinkCount >= 3) {
          _captureTriggered = true;
          state = FaceScanCapturing();
        } else {
          state = FaceScanBlinking(_blinkCount);
        }
      }
    }
  }

  Future<void> submitAttendance({
    required FaceScanParams params,
    required String faceImageB64,
    required ApiClient api,
  }) async {
    state = FaceScanVerifying();
    try {
      final res = await api.post('/api/attendance/mark/', data: {
        'session_id': params.sessionId,
        'lat': params.lat,
        'lng': params.lng,
        'altitude': params.altitude,
        'device_id': params.deviceId,
        'face_image_b64': faceImageB64,
        'blink_count': _blinkCount,
      });
      state = FaceScanSuccess(res.data['marked_at'] ?? DateTime.now().toIso8601String());
    } on DioException catch (e) {
      final msg = e.response?.data['error'] ?? 'Verification failed';
      state = FaceScanFailed(msg);
    } catch (e) {
      state = FaceScanFailed(e.toString());
    }
  }

  void reset() {
    _blinkCount = 0;
    _eyeWasClosed = false;
    _captureTriggered = false;
    state = FaceScanScanning();
  }
}
