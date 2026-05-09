import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';

// ── Face registration list ────────────────────────────────
final faceListProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final api = ref.read(apiClientProvider);
  final res = await api.get('/api/face/list/');
  return Map<String, dynamic>.from(res.data as Map);
});

// ── Face status for a specific student ────────────────────
final faceStatusProvider = FutureProvider.family<Map<String, dynamic>, String>(
  (ref, studentId) async {
    final api = ref.read(apiClientProvider);
    final res = await api.get('/api/face/status/$studentId/');
    return Map<String, dynamic>.from(res.data as Map);
  },
);

// ── Register state ─────────────────────────────────────────
abstract class FaceRegisterState {}
class FaceRegisterIdle        extends FaceRegisterState {}
class FaceRegisterLoading     extends FaceRegisterState {}
class FaceRegisterSuccess     extends FaceRegisterState {
  final String message;
  FaceRegisterSuccess(this.message);
}
class FaceRegisterError       extends FaceRegisterState {
  final String message;
  FaceRegisterError(this.message);
}

class FaceRegisterNotifier extends StateNotifier<FaceRegisterState> {
  final ApiClient _api;
  FaceRegisterNotifier(this._api) : super(FaceRegisterIdle());

  Future<void> registerFace({
    required String studentId,
    required String faceImageB64,
  }) async {
    state = FaceRegisterLoading();
    try {
      final res = await _api.post('/api/face/register/', data: {
        'student_id'    : studentId,
        'face_image_b64': faceImageB64,
      });
      state = FaceRegisterSuccess(
        res.data['message']?.toString() ?? 'Face registered successfully.',
      );
    } on Exception catch (e) {
      String msg = e.toString();
      // Extract DioException response error message
      if (msg.contains('"error"')) {
        try {
          final start = msg.indexOf('"error"') + 9;
          msg = msg.substring(start, msg.indexOf('"', start + 1));
        } catch (_) {}
      }
      state = FaceRegisterError(msg);
    }
  }

  Future<void> deleteFace(String studentId) async {
    state = FaceRegisterLoading();
    try {
      await _api.delete('/api/face/$studentId/');
      state = FaceRegisterSuccess('Face registration removed.');
    } on Exception catch (e) {
      state = FaceRegisterError(e.toString());
    }
  }

  void reset() => state = FaceRegisterIdle();
}

final faceRegisterProvider =
    StateNotifierProvider<FaceRegisterNotifier, FaceRegisterState>((ref) {
  return FaceRegisterNotifier(ref.read(apiClientProvider));
});
