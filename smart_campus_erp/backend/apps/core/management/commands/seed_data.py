from django.core.management.base import BaseCommand
from django.utils import timezone
from datetime import date, timedelta
import random
import string


class Command(BaseCommand):
    help = 'Seed production-quality test data for Smart Campus ERP'

    def add_arguments(self, parser):
        parser.add_argument(
            '--reset',
            action='store_true',
            help='Delete all existing data before seeding',
        )

    def handle(self, *args, **options):
        if options['reset']:
            self._reset_data()

        self.stdout.write(self.style.MIGRATE_HEADING(
            '\n=== Smart Campus ERP - Seeding Data ===\n'
        ))

        college      = self._seed_college()
        academic_year = self._seed_academic_year(college)
        dept         = self._seed_department(college)
        course       = self._seed_course(college, dept)
        divisions    = self._seed_divisions(college, course, academic_year)
        subjects     = self._seed_subjects(college, dept, course)
        users        = self._seed_users(college)
        room         = self._seed_virtual_room(college, users['college_admin'])
        allocations  = self._seed_allocations(
            college, subjects, users['teacher'], divisions, academic_year
        )
        student_profile = self._seed_student(
            college, users['student'], divisions[0], course, academic_year
        )
        self._seed_enrollments(student_profile, allocations, academic_year)
        self._seed_device(users['student'])
        self._seed_notifications(users, college)

        self._print_summary(college, users, room, subjects)

    def _reset_data(self):
        self.stdout.write('Resetting existing data...')
        from apps.attendance.models import AttendanceLog, AttendanceSession
        from apps.students.models   import StudentSubjectEnrollment, StudentProfile
        from apps.face_recognition.models import FaceDescriptor
        from apps.notifications.models    import Notification
        from apps.approvals.models        import ApprovalRequest
        from apps.academic.models         import SubjectAllocation
        from apps.accounts.models         import DeviceRegistry, User
        from apps.virtual_rooms.models    import VirtualRoom
        from apps.academic.models         import (
            Subject, Division, AcademicYear, Course, Department
        )
        from apps.tenants.models          import College

        AttendanceLog.objects.all().delete()
        AttendanceSession.objects.all().delete()
        StudentSubjectEnrollment.objects.all().delete()
        FaceDescriptor.objects.all().delete()
        StudentProfile.objects.all().delete()
        Notification.objects.all().delete()
        ApprovalRequest.objects.all().delete()
        SubjectAllocation.objects.all().delete()
        DeviceRegistry.objects.all().delete()
        VirtualRoom.objects.all().delete()
        Subject.objects.all().delete()
        Division.objects.all().delete()
        AcademicYear.objects.all().delete()
        Course.objects.all().delete()
        Department.objects.all().delete()
        User.objects.filter(is_superuser=False).delete()
        College.objects.all().delete()
        self.stdout.write(self.style.SUCCESS('Reset complete.'))

    def _seed_college(self):
        from apps.tenants.models import College
        college, created = College.objects.get_or_create(
            code='DEC',
            defaults={
                'name'        : 'Demo Engineering College',
                'email_domain': 'dec.edu',
                'address'     : '123 College Road, Pune, Maharashtra 411001',
                'phone'       : '020-12345678',
                'is_active'   : True,
            },
        )
        self.stdout.write(f'  College: {college.name}')
        return college

    def _seed_academic_year(self, college):
        from apps.academic.models import AcademicYear
        year, _ = AcademicYear.objects.get_or_create(
            college=college, name='2024-25',
            defaults={
                'start_date': date(2024, 7, 1),
                'end_date'  : date(2025, 5, 31),
                'is_current': True,
            },
        )
        self.stdout.write(f'  Academic Year: {year.name}')
        return year

    def _seed_department(self, college):
        from apps.academic.models import Department
        dept, _ = Department.objects.get_or_create(
            college=college, code='CE',
            defaults={'name': 'Computer Engineering', 'is_active': True},
        )
        self.stdout.write(f'  Department: {dept.name}')
        return dept

    def _seed_course(self, college, dept):
        from apps.academic.models import Course
        course, _ = Course.objects.get_or_create(
            college=college, code='BECE',
            defaults={
                'department'    : dept,
                'name'          : 'B.E. Computer Engineering',
                'duration_years': 4,
                'is_active'     : True,
            },
        )
        self.stdout.write(f'  Course: {course.name}')
        return course

    def _seed_divisions(self, college, course, academic_year):
        from apps.academic.models import Division
        divisions = []
        for name, year in [('A', 2), ('B', 2), ('A', 3)]:
            div, _ = Division.objects.get_or_create(
                course=course, academic_year=academic_year,
                name=name, year_of_study=year,
                defaults={
                    'college' : college,
                    'capacity': 60,
                    'is_active': True,
                },
            )
            divisions.append(div)
            self.stdout.write(
                f'  Division: Year {year} Div {name}'
            )
        return divisions

    def _seed_subjects(self, college, dept, course):
        from apps.academic.models import Subject
        subject_data = [
            ('Data Structures',         'DS101',  2, 3, 4, False),
            ('Algorithms',              'AL201',  2, 4, 4, False),
            ('Database Systems',        'DB301',  2, 3, 4, False),
            ('Operating Systems',       'OS401',  3, 5, 4, False),
            ('Computer Networks',       'CN501',  3, 6, 4, False),
            ('Data Structures Lab',     'DS101L', 2, 3, 2, True),
            ('Database Lab',            'DB301L', 2, 3, 2, True),
        ]
        subjects = []
        for name, code, year, sem, credits, is_lab in subject_data:
            s, _ = Subject.objects.get_or_create(
                college=college, code=code,
                defaults={
                    'department'  : dept,
                    'course'      : course,
                    'name'        : name,
                    'year_of_study': year,
                    'semester'    : sem,
                    'credits'     : credits,
                    'is_lab'      : is_lab,
                    'is_active'   : True,
                },
            )
            subjects.append(s)
        self.stdout.write(f'  Subjects: {len(subjects)} created')
        return subjects

    def _create_user(self, email, password, first, last,
                     role, college, approved=True):
        from apps.accounts.models import User
        user, created = User.objects.get_or_create(
            email=email,
            defaults={
                'first_name' : first,
                'last_name'  : last,
                'role'       : role,
                'college'    : college,
                'is_active'  : approved,
                'is_approved': approved,
                'is_staff'   : role == 'super_admin',
                'is_superuser': role == 'super_admin',
            },
        )
        if created:
            user.set_password(password)
            user.save()
        return user

    def _seed_users(self, college):
        users = {}

        users['super_admin'] = self._create_user(
            'superadmin@platform.com', 'Admin@123',
            'Super', 'Admin', 'super_admin', None,
        )
        users['college_admin'] = self._create_user(
            'admin@dec.edu', 'Admin@123',
            'College', 'Admin', 'college_admin', college,
        )
        users['principal'] = self._create_user(
            'principal@dec.edu', 'Admin@123',
            'Dr. Ramesh', 'Sharma', 'principal', college,
        )
        users['hod'] = self._create_user(
            'hod@dec.edu', 'Admin@123',
            'Prof. Sunita', 'Patil', 'hod', college,
        )
        users['teacher'] = self._create_user(
            'teacher@dec.edu', 'Admin@123',
            'Prof. Anjali', 'Desai', 'teacher', college,
        )
        users['teacher2'] = self._create_user(
            'teacher2@dec.edu', 'Admin@123',
            'Prof. Vikram', 'Joshi', 'teacher', college,
        )
        users['lab_assistant'] = self._create_user(
            'labassistant@dec.edu', 'Admin@123',
            'Nikhil', 'More', 'lab_assistant', college,
        )
        users['student'] = self._create_user(
            'student@dec.edu', 'Admin@123',
            'Rahul', 'Kulkarni', 'student', college,
        )
        users['student2'] = self._create_user(
            'student2@dec.edu', 'Admin@123',
            'Priya', 'Sharma', 'student', college,
        )

        # Update HOD in department
        from apps.academic.models import Department
        Department.objects.filter(college=college, code='CE').update(
            hod=users['hod']
        )

        self.stdout.write(f'  Users: {len(users)} created/verified')
        return users

    def _seed_virtual_room(self, college, created_by):
        from apps.virtual_rooms.models import VirtualRoom
        rooms_data = [
            ('Room 301',        'A Block', 3, '18.5204300', '73.8567400', 30.0, 0.0,  50.0),
            ('Room 302',        'A Block', 3, '18.5205000', '73.8568000', 30.0, 0.0,  50.0),
            ('Computer Lab 1',  'B Block', 1, '18.5210000', '73.8570000', 25.0, 0.0,  15.0),
            ('Seminar Hall',    'Main',    0, '18.5200000', '73.8565000', 50.0, 0.0,   8.0),
        ]
        first_room = None
        for name, building, floor, lat, lng, radius, min_alt, max_alt in rooms_data:
            room, _ = VirtualRoom.objects.get_or_create(
                college=college, name=name,
                defaults={
                    'building'     : building,
                    'floor_number' : floor,
                    'center_lat'   : lat,
                    'center_lng'   : lng,
                    'radius_meters': radius,
                    'min_altitude' : min_alt,
                    'max_altitude' : max_alt,
                    'is_active'    : True,
                    'created_by'   : created_by,
                },
            )
            if first_room is None:
                first_room = room
        self.stdout.write(f'  Virtual Rooms: {len(rooms_data)} created')
        return first_room

    def _seed_allocations(self, college, subjects, teacher,
                          divisions, academic_year):
        from apps.academic.models import SubjectAllocation
        allocations = []
        # Allocate year-2 theory subjects to Div A Year 2
        div_a_y2 = divisions[0]
        for subj in subjects[:3]:  # DS101, AL201, DB301
            alloc, _ = SubjectAllocation.objects.get_or_create(
                subject=subj, teacher=teacher,
                division=div_a_y2, academic_year=academic_year,
                defaults={'college': college, 'is_active': True},
            )
            allocations.append(alloc)
        self.stdout.write(
            f'  Allocations: {len(allocations)} created for {teacher.first_name}'
        )
        return allocations

    def _seed_student(self, college, user, division, course, academic_year):
        from apps.students.models import StudentProfile
        profile, _ = StudentProfile.objects.get_or_create(
            prn='DEC2024001',
            defaults={
                'user'          : user,
                'college'       : college,
                'division'      : division,
                'course'        : course,
                'academic_year' : academic_year,
                'roll_number'   : '01',
                'year_of_study' : 2,
                'face_registered': False,
                'is_active'     : True,
            },
        )
        # Seed second student
        from apps.accounts.models import User as UserModel
        student2 = UserModel.objects.get(email='student2@dec.edu')
        StudentProfile.objects.get_or_create(
            prn='DEC2024002',
            defaults={
                'user'          : student2,
                'college'       : college,
                'division'      : division,
                'course'        : course,
                'academic_year' : academic_year,
                'roll_number'   : '02',
                'year_of_study' : 2,
                'face_registered': False,
                'is_active'     : True,
            },
        )
        self.stdout.write('  Students: 2 profiles created')
        return profile

    def _seed_enrollments(self, student_profile, allocations, academic_year):
        from apps.students.models import (
            StudentProfile, StudentSubjectEnrollment
        )
        # Enroll primary student
        count = 0
        for alloc in allocations:
            _, created = StudentSubjectEnrollment.objects.get_or_create(
                student=student_profile,
                subject_allocation=alloc,
                defaults={
                    'academic_year': academic_year,
                    'is_active'    : True,
                },
            )
            if created:
                count += 1
        # Enroll second student
        from apps.accounts.models import User
        student2_user = User.objects.get(email='student2@dec.edu')
        profile2 = StudentProfile.objects.get(user=student2_user)
        for alloc in allocations:
            StudentSubjectEnrollment.objects.get_or_create(
                student=profile2,
                subject_allocation=alloc,
                defaults={
                    'academic_year': academic_year,
                    'is_active'    : True,
                },
            )
        self.stdout.write(
            f'  Enrollments: {len(allocations) * 2} created (2 students × {len(allocations)} subjects)'
        )

    def _seed_device(self, student_user):
        from apps.accounts.models import DeviceRegistry
        DeviceRegistry.objects.get_or_create(
            user=student_user,
            device_id='TEST_DEVICE_001',
            defaults={
                'device_name': 'Test Android Phone',
                'platform'   : 'android',
                'is_active'  : True,
            },
        )
        student_user.device_id = 'TEST_DEVICE_001'
        student_user.save(update_fields=['device_id'])
        self.stdout.write('  Device: TEST_DEVICE_001 registered for student')

    def _seed_notifications(self, users, college):
        from apps.notifications.models import Notification
        notifs = [
            (users['student'], users['college_admin'],
             'Welcome to Smart Campus!',
             'Your student account has been created and approved. '
             'You can now mark attendance using face recognition.',
             'system'),
            (users['teacher'], users['college_admin'],
             'Subject Allocated',
             'Data Structures (DS101) has been allocated to you for '
             'Division A Year 2. You can now create attendance sessions.',
             'system'),
            (users['principal'], users['college_admin'],
             'Setup Complete',
             'College setup is complete. All users, subjects, and '
             'virtual rooms have been configured.',
             'system'),
        ]
        count = 0
        for recipient, sender, title, message, notif_type in notifs:
            _, created = Notification.objects.get_or_create(
                recipient=recipient,
                title=title,
                defaults={
                    'college'    : college,
                    'sender'     : sender,
                    'message'    : message,
                    'notif_type' : notif_type,
                    'is_read'    : False,
                },
            )
            if created:
                count += 1
        self.stdout.write(f'  Notifications: {count} seeded')

    def _print_summary(self, college, users, room, subjects):
        self.stdout.write('\n' + '=' * 60)
        self.stdout.write(self.style.SUCCESS('SEED DATA COMPLETE'))
        self.stdout.write('=' * 60)
        self.stdout.write(f'College      : {college.name} ({college.code})')
        self.stdout.write(f'Domain       : {college.email_domain}')
        self.stdout.write(f'Room 301     : lat={room.center_lat}, lng={room.center_lng}, radius={room.radius_meters}m')
        self.stdout.write(f'Subjects     : {len(subjects)} created')
        self.stdout.write('')
        self.stdout.write('LOGIN CREDENTIALS:')
        self.stdout.write('-' * 60)
        creds = [
            ('Super Admin',   'superadmin@platform.com', 'Admin@123', 'Email login only'),
            ('College Admin', 'admin@dec.edu',           'Admin@123', 'Email login'),
            ('Principal',     'principal@dec.edu',       'Admin@123', 'Email login'),
            ('HOD',           'hod@dec.edu',             'Admin@123', 'Email login'),
            ('Teacher',       'teacher@dec.edu',         'Admin@123', 'Email login'),
            ('Teacher 2',     'teacher2@dec.edu',        'Admin@123', 'Email login'),
            ('Lab Assistant', 'labassistant@dec.edu',    'Admin@123', 'Email login'),
            ('Student 1',     'student@dec.edu',         'Admin@123', 'Email or PRN: DEC2024001'),
            ('Student 2',     'student2@dec.edu',        'Admin@123', 'Email or PRN: DEC2024002'),
        ]
        for role, email, pwd, note in creds:
            self.stdout.write(
                f'{role:<16} {email:<32} {pwd}  ({note})'
            )
        self.stdout.write('=' * 60 + '\n')
