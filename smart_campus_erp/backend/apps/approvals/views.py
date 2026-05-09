from django.utils import timezone
from rest_framework.views       import APIView
from rest_framework.permissions import IsAuthenticated
from rest_framework.response    import Response
from apps.accounts.permissions  import IsPrincipal, IsCollegeAdmin, IsSuperAdmin
from apps.accounts.models       import User
from .models                    import ApprovalRequest


class PendingApprovalListView(APIView):
    permission_classes = [IsPrincipal | IsCollegeAdmin | IsSuperAdmin]

    def get(self, request):
        qs = ApprovalRequest.objects.select_related(
            'user', 'user__college'
        ).filter(status='pending')

        if request.user.role != 'super_admin':
            qs = qs.filter(college=request.user.college)

        now = timezone.now()
        data = [
            {
                'approval_id'   : str(a.id),
                'user_id'       : str(a.user.id),
                'full_name'     : a.user.get_full_name(),
                'email'         : a.user.email,
                'role'          : a.requested_role,
                'phone'         : a.user.phone,
                'college_name'  : a.user.college.name
                                  if a.user.college else None,
                'created_at'    : a.created_at.isoformat(),
                'days_waiting'  : (now - a.created_at).days,
            }
            for a in qs.order_by('created_at')
        ]
        return Response({'approvals': data, 'count': len(data)})
