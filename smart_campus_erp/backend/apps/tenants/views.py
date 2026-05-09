from django.db import IntegrityError
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from apps.accounts.permissions import IsSuperAdmin
from .models import College


class CollegeListCreateView(APIView):
    def get_permissions(self):
        if self.request.method == 'GET':
            return []  # AllowAny for list
        return [IsSuperAdmin()]

    def get(self, request):
        search    = request.query_params.get('search', '')
        is_active = request.query_params.get('is_active')

        qs = College.objects.all().order_by('name')

        if search:
            qs = qs.filter(name__icontains=search)
        if is_active is not None:
            qs = qs.filter(is_active=is_active.lower() == 'true')

        data = [
            {
                'id'          : str(c.id),
                'name'        : c.name,
                'code'        : c.code,
                'email_domain': c.email_domain,
                'address'     : c.address,
                'phone'       : c.phone,
                'logo_url'    : c.logo_url,
                'is_active'   : c.is_active,
                'created_at'  : c.created_at.isoformat(),
                'user_count'  : c.users.count(),
            }
            for c in qs
        ]

        return Response({
            'colleges'      : data,
            'total'         : qs.count(),
            'active_count'  : qs.filter(is_active=True).count(),
            'inactive_count': qs.filter(is_active=False).count(),
        })

    def post(self, request):
        name         = request.data.get('name', '').strip()
        code         = request.data.get('code', '').strip().upper()
        email_domain = request.data.get('email_domain', '').strip().lower()
        address      = request.data.get('address', '').strip()
        phone        = request.data.get('phone', '').strip()
        logo_url     = request.data.get('logo_url', '').strip()

        if not name:
            return Response(
                {'error': 'College name is required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if not code:
            return Response(
                {'error': 'College code is required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if not email_domain:
            return Response(
                {'error': 'Email domain is required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if not address:
            return Response(
                {'error': 'Address is required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            college = College.objects.create(
                name         = name,
                code         = code,
                email_domain = email_domain,
                address      = address,
                phone        = phone,
                logo_url     = logo_url,
                is_active    = True,
            )
            return Response(
                {
                    'success': True,
                    'message': f'College "{college.name}" created successfully.',
                    'college': {
                        'id'          : str(college.id),
                        'name'        : college.name,
                        'code'        : college.code,
                        'email_domain': college.email_domain,
                        'address'     : college.address,
                        'phone'       : college.phone,
                        'is_active'   : college.is_active,
                        'created_at'  : college.created_at.isoformat(),
                        'user_count'  : 0,
                    },
                },
                status=status.HTTP_201_CREATED,
            )
        except IntegrityError as e:
            if 'code' in str(e):
                return Response(
                    {'error': f'College code "{code}" already exists.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            if 'email_domain' in str(e):
                return Response(
                    {'error': f'Email domain "{email_domain}" already exists.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            return Response(
                {'error': 'A college with this code or domain already exists.'},
                status=status.HTTP_400_BAD_REQUEST,
            )


class CollegeDetailView(APIView):
    permission_classes = [IsSuperAdmin]

    def _get_college(self, college_id):
        try:
            return College.objects.get(id=college_id)
        except College.DoesNotExist:
            return None

    def get(self, request, college_id):
        college = self._get_college(college_id)
        if not college:
            return Response({'error': 'College not found.'}, status=404)

        from apps.accounts.models import User
        users = User.objects.filter(college=college)

        return Response({
            'id'          : str(college.id),
            'name'        : college.name,
            'code'        : college.code,
            'email_domain': college.email_domain,
            'address'     : college.address,
            'phone'       : college.phone,
            'logo_url'    : college.logo_url,
            'is_active'   : college.is_active,
            'created_at'  : college.created_at.isoformat(),
            'updated_at'  : college.updated_at.isoformat(),
            'stats': {
                'total_users'    : users.count(),
                'teachers'       : users.filter(role='teacher').count(),
                'students'       : users.filter(role='student').count(),
                'approved_users' : users.filter(is_approved=True).count(),
                'pending_users'  : users.filter(is_approved=False).count(),
            },
        })

    def put(self, request, college_id):
        college = self._get_college(college_id)
        if not college:
            return Response({'error': 'College not found.'}, status=404)

        allowed = ['name', 'address', 'phone', 'logo_url']
        for field in allowed:
            if field in request.data:
                setattr(college, field, request.data[field])

        if 'code' in request.data:
            new_code = request.data['code'].strip().upper()
            if College.objects.filter(code=new_code).exclude(id=college.id).exists():
                return Response(
                    {'error': f'Code "{new_code}" is already used by another college.'},
                    status=400,
                )
            college.code = new_code

        if 'email_domain' in request.data:
            new_domain = request.data['email_domain'].strip().lower()
            if College.objects.filter(email_domain=new_domain).exclude(id=college.id).exists():
                return Response(
                    {'error': f'Domain "{new_domain}" is already used by another college.'},
                    status=400,
                )
            college.email_domain = new_domain

        college.save()
        return Response({
            'success': True,
            'message': f'College "{college.name}" updated successfully.',
        })

    def delete(self, request, college_id):
        college = self._get_college(college_id)
        if not college:
            return Response({'error': 'College not found.'}, status=404)

        college.is_active = False
        college.save(update_fields=['is_active'])

        return Response({
            'success': True,
            'message': f'College "{college.name}" deactivated successfully.',
        })


class CollegeActivateView(APIView):
    permission_classes = [IsSuperAdmin]

    def post(self, request, college_id):
        try:
            college = College.objects.get(id=college_id)
        except College.DoesNotExist:
            return Response({'error': 'College not found.'}, status=404)

        college.is_active = True
        college.save(update_fields=['is_active'])

        return Response({
            'success': True,
            'message': f'College "{college.name}" activated successfully.',
        })
