import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';

// ── Notifications list ─────────────────────────────────────
final notificationsProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final api = ref.read(apiClientProvider);
  final res = await api.get('/api/notifications/');
  return Map<String, dynamic>.from(res.data as Map);
});

// ── Unread count (for sidebar badge) ──────────────────────
final unreadCountProvider = FutureProvider.autoDispose<int>((ref) async {
  // Keep alive for 30 seconds to prevent sidebar badge flicker
  final link = ref.keepAlive();
  Future.delayed(const Duration(seconds: 30), link.close);
  final api = ref.read(apiClientProvider);
  final res = await api.get('/api/notifications/unread-count/');
  return res.data['unread_count'] as int? ?? 0;
});

// ── Mark read state ────────────────────────────────────────
class NotificationNotifier extends StateNotifier<AsyncValue<void>> {
  final ApiClient _api;
  final Ref       _ref;

  NotificationNotifier(this._api, this._ref)
      : super(const AsyncValue.data(null));

  Future<void> markRead(String notifId) async {
    try {
      await _api.post('/api/notifications/$notifId/read/');
      _ref.invalidate(notificationsProvider);
      _ref.invalidate(unreadCountProvider);
    } catch (_) {}
  }

  Future<void> markAllRead() async {
    state = const AsyncValue.loading();
    try {
      await _api.post('/api/notifications/read-all/');
      _ref.invalidate(notificationsProvider);
      _ref.invalidate(unreadCountProvider);
      state = const AsyncValue.data(null);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }
}

final notificationNotifierProvider =
    StateNotifierProvider<NotificationNotifier, AsyncValue<void>>((ref) {
  return NotificationNotifier(ref.read(apiClientProvider), ref);
});
