from django.utils            import timezone
from rest_framework.views    import APIView
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework          import status
from .models                 import Notification


class NotificationListView(APIView):
    """
    GET /api/notifications/
    Returns all notifications for the logged-in user.
    Query params:
      is_read=true/false  → filter by read status
      notif_type=approval/attendance/alert/system
      limit=50            → number of results
    """
    permission_classes = [IsAuthenticated]

    def get(self, request):
        qs = Notification.objects.filter(
            recipient=request.user
        ).select_related('sender').order_by('-created_at')

        is_read    = request.query_params.get('is_read')
        notif_type = request.query_params.get('notif_type')
        limit      = int(request.query_params.get('limit', 50))

        if is_read is not None:
            qs = qs.filter(is_read=is_read.lower() == 'true')
        if notif_type:
            qs = qs.filter(notif_type=notif_type)

        qs          = qs[:limit]
        unread_count = Notification.objects.filter(
            recipient=request.user, is_read=False
        ).count()

        data = [
            {
                'id'          : str(n.id),
                'title'       : n.title,
                'message'     : n.message,
                'notif_type'  : n.notif_type,
                'is_read'     : n.is_read,
                'read_at'     : n.read_at.isoformat() if n.read_at else None,
                'created_at'  : n.created_at.isoformat(),
                'sender_name' : n.sender.get_full_name() if n.sender else 'System',
                'time_ago'    : _time_ago(n.created_at),
            }
            for n in qs
        ]

        return Response({
            'notifications': data,
            'unread_count' : unread_count,
            'total'        : len(data),
        })


class MarkNotificationReadView(APIView):
    """POST /api/notifications/{notif_id}/read/"""
    permission_classes = [IsAuthenticated]

    def post(self, request, notif_id):
        updated = Notification.objects.filter(
            id        = notif_id,
            recipient = request.user,
            is_read   = False,
        ).update(is_read=True, read_at=timezone.now())

        return Response({
            'success': True,
            'updated': updated,
        })


class MarkAllReadView(APIView):
    """POST /api/notifications/read-all/"""
    permission_classes = [IsAuthenticated]

    def post(self, request):
        count = Notification.objects.filter(
            recipient = request.user,
            is_read   = False,
        ).update(is_read=True, read_at=timezone.now())

        return Response({
            'success'        : True,
            'marked_as_read' : count,
        })


class UnreadCountView(APIView):
    """GET /api/notifications/unread-count/"""
    permission_classes = [IsAuthenticated]

    def get(self, request):
        count = Notification.objects.filter(
            recipient = request.user,
            is_read   = False,
        ).count()
        return Response({'unread_count': count})


def _time_ago(dt) -> str:
    """Return human-readable time difference."""
    from django.utils import timezone as tz
    now   = tz.now()
    delta = now - dt
    secs  = int(delta.total_seconds())
    if secs < 60:
        return 'Just now'
    if secs < 3600:
        return f'{secs // 60}m ago'
    if secs < 86400:
        return f'{secs // 3600}h ago'
    return f'{secs // 86400}d ago'
