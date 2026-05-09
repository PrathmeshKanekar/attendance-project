import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/layout/app_layout.dart';
import '../../core/widgets/empty_state_widget.dart';
import '../../core/widgets/error_widget.dart';
import '../../core/widgets/loading_widget.dart';
import 'notification_providers.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async  = ref.watch(notificationsProvider);
    final notifier = ref.read(notificationNotifierProvider.notifier);

    return AppLayout(
      title  : 'Notifications',
      actions: [
        TextButton.icon(
          onPressed: () => notifier.markAllRead(),
          icon     : const Icon(Icons.done_all_rounded, size: 18),
          label    : const Text('Mark all read'),
          style    : TextButton.styleFrom(
            foregroundColor: AppColors.primaryLight,
          ),
        ),
        IconButton(
          icon     : const Icon(Icons.refresh_rounded),
          onPressed: () => ref.invalidate(notificationsProvider),
        ),
      ],
      child: async.when(
        loading: () => const LoadingWidget(message: 'Loading notifications...'),
        error  : (e, _) => AppErrorWidget(
          message: e.toString(),
          onRetry: () => ref.invalidate(notificationsProvider),
        ),
        data   : (data) {
          final notifications = List<Map<String, dynamic>>.from(
            data['notifications'] as List,
          );
          final unreadCount = data['unread_count'] as int? ?? 0;

          if (notifications.isEmpty) {
            return const EmptyStateWidget(
              message : 'No notifications yet',
              icon    : Icons.notifications_off_rounded,
              subtitle: 'Notifications will appear here',
            );
          }

          return Column(
            children: [

              // ── Unread count banner ──────────────────────
              if (unreadCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 10,
                  ),
                  color: AppColors.primaryLight.withOpacity(0.08),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color       : AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$unreadCount unread',
                          style: const TextStyle(
                            color    : Colors.white,
                            fontSize : 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => notifier.markAllRead(),
                        child    : const Text('Mark all read'),
                      ),
                    ],
                  ),
                ),

              // ── Notifications list ──────────────────────
              Expanded(
                child: ListView.separated(
                  padding        : const EdgeInsets.symmetric(vertical: 8),
                  itemCount      : notifications.length,
                  separatorBuilder: (_, __) => const Divider(
                    height  : 1,
                    indent  : 72,
                    endIndent: 20,
                    color   : AppColors.borderColor,
                  ),
                  itemBuilder    : (context, i) {
                    final n = notifications[i];
                    return _NotificationTile(
                      notification: n,
                      onTap: () => notifier.markRead(n['id'].toString()),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}


// ── Notification tile ──────────────────────────────────────
class _NotificationTile extends StatelessWidget {
  final Map<String, dynamic> notification;
  final VoidCallback         onTap;

  const _NotificationTile({
    required this.notification,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isRead    = notification['is_read'] == true;
    final notifType = notification['notif_type']?.toString() ?? 'system';

    return InkWell(
      onTap: isRead ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        color  : isRead ? null : AppColors.primaryLight.withOpacity(0.04),
        child  : Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // Icon circle
            Container(
              width : 44,
              height: 44,
              decoration: BoxDecoration(
                color: _typeColor(notifType).withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _typeIcon(notifType),
                color: _typeColor(notifType),
                size : 22,
              ),
            ),

            const SizedBox(width: 12),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Unread dot
                      if (!isRead) ...[
                        Container(
                          width : 8, height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.primaryLight,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          notification['title']?.toString() ?? '',
                          style: TextStyle(
                            fontWeight: isRead
                                ? FontWeight.w500
                                : FontWeight.w700,
                            fontSize: 14,
                            color   : AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        notification['time_ago']?.toString() ?? '',
                        style: const TextStyle(
                          color  : AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification['message']?.toString() ?? '',
                    style: TextStyle(
                      color  : isRead
                          ? AppColors.textSecondary
                          : AppColors.textPrimary.withOpacity(0.80),
                      fontSize: 13,
                    ),
                    maxLines : 2,
                    overflow : TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'From: ${notification['sender_name'] ?? "System"}',
                    style: const TextStyle(
                      color  : AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'approval'   : return Icons.check_circle_outline_rounded;
      case 'attendance' : return Icons.fact_check_rounded;
      case 'alert'      : return Icons.warning_amber_rounded;
      default           : return Icons.notifications_rounded;
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'approval'   : return AppColors.success;
      case 'attendance' : return AppColors.primaryLight;
      case 'alert'      : return AppColors.warning;
      default           : return AppColors.textSecondary;
    }
  }
}
