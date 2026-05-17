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
            return []  # AllowAny for registration/list
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
        from django.db import transaction
        from apps.accounts.models import User, UserRole
        import secrets
        import string

        # College Details
        name         = request.data.get('name', '').strip()
        code         = request.data.get('code', '').strip().upper()
        email_domain = request.data.get('email_domain', '').strip().lower()
        address      = request.data.get('address', '').strip()
        phone        = request.data.get('phone', '').strip()
        logo_url     = request.data.get('logo_url', '').strip()

        # Admin Details
        admin_email = request.data.get('admin_email', '').strip().lower()
        admin_first = request.data.get('admin_first_name', '').strip()
        admin_last  = request.data.get('admin_last_name', '').strip()
        admin_phone = request.data.get('admin_phone', '').strip()

        # Validations
        if not all([name, code, email_domain, address, admin_email, admin_first]):
            return Response(
                {'error': 'College details and basic Admin info (email, name) are required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if User.objects.filter(email=admin_email).exists():
            return Response(
                {'error': f'A user with email "{admin_email}" already exists.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            with transaction.atomic():
                # 1. Create College
                college = College.objects.create(
                    name         = name,
                    code         = code,
                    email_domain = email_domain,
                    address      = address,
                    phone        = phone,
                    logo_url     = logo_url,
                    is_active    = True,
                )

                # 2. Generate Secure Password
                alphabet = string.ascii_letters + string.digits
                temp_password = ''.join(secrets.choice(alphabet) for i in range(10))

                # 3. Create College Admin User
                admin_user = User.objects.create(
                    email      = admin_email,
                    first_name = admin_first,
                    last_name  = admin_last,
                    phone      = admin_phone,
                    role       = UserRole.COLLEGE_ADMIN,
                    college    = college,
                    is_active  = True,
                    is_approved= True,
                )
                admin_user.set_password(temp_password)
                admin_user.save()

            return Response(
                {
                    'success': True,
                    'message': f'College "{college.name}" and Admin account created successfully.',
                    'college': {
                        'id'   : str(college.id),
                        'name' : college.name,
                        'code' : college.code,
                    },
                    'admin_credentials': {
                        'email'    : admin_email,
                        'password' : temp_password,
                        'note'     : 'Please share these credentials securely with the College Admin.'
                    }
                },
                status=status.HTTP_201_CREATED,
            )

        except IntegrityError as e:
            error_msg = str(e)
            if 'code' in error_msg:
                return Response({'error': f'College code "{code}" already exists.'}, status=400)
            if 'email_domain' in error_msg:
                return Response({'error': f'Email domain "{email_domain}" already exists.'}, status=400)
            return Response({'error': 'A database integrity error occurred.'}, status=400)
        except Exception as e:
            return Response({'error': f'An unexpected error occurred: {str(e)}'}, status=500)


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
