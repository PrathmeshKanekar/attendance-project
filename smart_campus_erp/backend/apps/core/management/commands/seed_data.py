import random
import uuid
import string
from datetime import date, datetime, timedelta, time
from django.core.management.base import BaseCommand
from django.utils import timezone
from django.contrib.auth.hashers import make_password

# Import all models safely
from apps.tenants.models import College
from apps.academic.models import (
    Department, Course, AcademicYear, Division, Subject, SubjectAllocation, Semester, Timetable
)
from apps.accounts.models import User, DeviceRegistry
from apps.staff.models import StaffProfile, LabAssistantDepartment
from apps.students.models import StudentProfile, StudentSubjectEnrollment
from apps.attendance.models import AttendanceSession, AttendanceLog, ManualAttendanceRequest
from apps.virtual_rooms.models import VirtualRoom, RoomCorner
from apps.face_recognition.models import FaceDescriptor, FaceRegistrationImage
from apps.notifications.models import Notification, NoticeBoard
from apps.audit.models import AuditLog
from apps.approvals.models import ApprovalRequest


class Command(BaseCommand):
    help = 'Seed comprehensive, production-grade test data for Smart Campus ERP'

    def add_arguments(self, parser):
        parser.add_argument(
            '--reset',
            action='store_true',
            help='Delete all existing data before seeding',
        )
        parser.add_argument(
            '--students-count',
            type=int,
            default=300,
            help='Number of realistic students to seed (default: 300)',
        )

    def handle(self, *args, **options):
        reset_active = options['reset']
        students_count = options['students_count']

        if reset_active:
            self._reset_data()

        self.stdout.write(self.style.MIGRATE_HEADING(
            '\n=== Smart Campus ERP - Seeding Industrial Test Data ===\n'
        ))

        # 1. Tenant (College)
        college = self._seed_college()

        # 2. Academic Year
        academic_year = self._seed_academic_year(college)

        # 3. Departments
        departments = self._seed_departments(college)

        # 4. Courses
        courses = self._seed_courses(college, departments)

        # 5. Semesters
        semesters = self._seed_semesters(college, courses, academic_year)

        # 6. Core Staff & Authorities (Super Admin, Principal, HODs, Teachers, Lab Assistants)
        users = self._seed_staff_users(college, departments)

        # 7. Update HOD fields on Department models
        self._assign_department_hods(departments, users)

        # 8. Lab Assistant Dynamic Multi-Department RBAC assignments
        self._seed_lab_assistant_rbac(users, departments)

        # 9. Divisions (A and B across different years)
        divisions = self._seed_divisions(college, courses, academic_year, users)

        # 10. Subjects (Theory and Practical Labs)
        subjects = self._seed_subjects(college, departments, courses)

        # 11. Virtual Geofenced Rooms & Bounding Corners
        rooms = self._seed_virtual_rooms(college, users['admin'], departments)

        # 12. Subject Allocations
        allocations = self._seed_subject_allocations(college, subjects, divisions, academic_year, users)

        # 13. Timetable Grid
        self._seed_timetable_grid(college, divisions, allocations)

        # 14. Bulk Student Registrations (200-500)
        student_profiles = self._seed_students_bulk(college, divisions, courses, academic_year, students_count)

        # 15. Student Enrollments & Biometrics (Face Descriptor + Device Registry)
        self._seed_student_enrollments_and_biometrics(student_profiles, allocations, academic_year)

        # 16. Historical Attendance Logging System (30-day timeline)
        self._seed_historical_attendance(college, allocations, student_profiles, rooms)

        # 17. Notice Boards & Operational Notifications
        self._seed_notifications_and_notices(college, users, departments)

        # 18. System Operations Audit Logs
        self._seed_audit_logs(college, users)

        # Print beautiful production summary
        self._print_production_summary(college, users, departments, students_count)

    def _reset_data(self):
        self.stdout.write(self.style.WARNING('Resetting existing data...'))
        
        AuditLog.objects.all().delete()
        Notification.objects.all().delete()
        NoticeBoard.objects.all().delete()
        AttendanceLog.objects.all().delete()
        ManualAttendanceRequest.objects.all().delete()
        AttendanceSession.objects.all().delete()
        FaceDescriptor.objects.all().delete()
        FaceRegistrationImage.objects.all().delete()
        StudentSubjectEnrollment.objects.all().delete()
        StudentProfile.objects.all().delete()
        LabAssistantDepartment.objects.all().delete()
        StaffProfile.objects.all().delete()
        ApprovalRequest.objects.all().delete()
        DeviceRegistry.objects.all().delete()
        
        # Clear m2m tables
        for dept in Department.objects.all():
            dept.notices.clear()

        Timetable.objects.all().delete()
        SubjectAllocation.objects.all().delete()
        RoomCorner.objects.all().delete()
        VirtualRoom.objects.all().delete()
        Subject.objects.all().delete()
        Division.objects.all().delete()
        Semester.objects.all().delete()
        AcademicYear.objects.all().delete()
        Course.objects.all().delete()
        
        # Set HODs to Null first to avoid cascade delete block
        Department.objects.all().update(hod=None)
        Department.objects.all().delete()
        
        # Delete non-superusers
        User.objects.filter(is_superuser=False).delete()
        College.objects.all().delete()
        
        self.stdout.write(self.style.SUCCESS('Reset complete.'))

    def _seed_college(self):
        college, _ = College.objects.get_or_create(
            code='DEC',
            defaults={
                'name': 'Demo Engineering College',
                'email_domain': 'dec.edu',
                'address': '123 Tech Campus, Pune, Maharashtra 411008',
                'phone': '020-27891234',
                'is_active': True,
            }
        )
        self.stdout.write(f'[OK] College: {college.name}')
        return college

    def _seed_academic_year(self, college):
        year, _ = AcademicYear.objects.get_or_create(
            college=college,
            name='2024-25',
            defaults={
                'start_date': date(2024, 6, 1),
                'end_date': date(2025, 4, 30),
                'is_current': True,
            }
        )
        self.stdout.write(f'[OK] Academic Year: {year.name}')
        return year

    def _seed_departments(self, college):
        dept_data = [
            ('CE', 'Computer Engineering'),
            ('IT', 'Information Technology'),
            ('ME', 'Mechanical Engineering'),
            ('EXTC', 'Electronics & Telecommunication'),
            ('AIDS', 'AI & Data Science'),
            ('CIVIL', 'Civil Engineering'),
        ]
        depts = {}
        for code, name in dept_data:
            dept, _ = Department.objects.get_or_create(
                college=college,
                code=code,
                defaults={'name': name, 'is_active': True}
            )
            depts[code] = dept
        self.stdout.write(f'[OK] Seeded {len(depts)} Departments.')
        return depts

    def _seed_courses(self, college, departments):
        courses = {}
        for code, dept in departments.items():
            course, _ = Course.objects.get_or_create(
                college=college,
                code=f'BE{code}',
                defaults={
                    'department': dept,
                    'name': f'B.E. {dept.name}',
                    'duration_years': 4,
                    'is_active': True,
                }
            )
            courses[code] = course
        self.stdout.write(f'[OK] Seeded {len(courses)} Courses.')
        return courses

    def _seed_semesters(self, college, courses, academic_year):
        semesters = []
        for code, course in courses.items():
            # Seed Year 2 Sem 3
            sem3, _ = Semester.objects.get_or_create(
                college=college,
                course=course,
                academic_year=academic_year,
                semester_number=3,
                defaults={
                    'start_date': date(2024, 6, 15),
                    'end_date': date(2024, 11, 30),
                    'is_active': True,
                }
            )
            # Seed Year 3 Sem 5
            sem5, _ = Semester.objects.get_or_create(
                college=college,
                course=course,
                academic_year=academic_year,
                semester_number=5,
                defaults={
                    'start_date': date(2024, 6, 15),
                    'end_date': date(2024, 11, 30),
                    'is_active': True,
                }
            )
            semesters.extend([sem3, sem5])
        self.stdout.write(f'[OK] Seeded semesters for all courses.')
        return semesters

    def _seed_staff_users(self, college, departments):
        users = {}
        hashed_pwd = make_password('Admin@123')

        # Super Admin
        super_admin, created = User.objects.get_or_create(
            email='superadmin@platform.com',
            defaults={
                'first_name': 'Super',
                'last_name': 'Admin',
                'role': 'super_admin',
                'is_active': True,
                'is_approved': True,
                'is_staff': True,
                'is_superuser': True,
                'password': hashed_pwd,
            }
        )
        users['super_admin'] = super_admin

        # College Admin
        admin, _ = User.objects.get_or_create(
            email='admin@dec.edu',
            defaults={
                'first_name': 'College',
                'last_name': 'Admin',
                'role': 'college_admin',
                'college': college,
                'is_active': True,
                'is_approved': True,
                'password': hashed_pwd,
            }
        )
        users['admin'] = admin

        # Principal
        principal, _ = User.objects.get_or_create(
            email='principal@dec.edu',
            defaults={
                'first_name': 'Ramesh',
                'last_name': 'Sharma',
                'role': 'principal',
                'college': college,
                'is_active': True,
                'is_approved': True,
                'password': hashed_pwd,
            }
        )
        users['principal'] = principal

        # Department HODs
        hod_names = {
            'CE': ('Sunita', 'Patil'),
            'IT': ('Anil', 'Verma'),
            'ME': ('Suresh', 'Joshi'),
            'EXTC': ('Amit', 'Shah'),
            'AIDS': ('Meera', 'Nair'),
            'CIVIL': ('Karan', 'Deshmukh'),
        }
        for code, dept in departments.items():
            first, last = hod_names[code]
            hod, _ = User.objects.get_or_create(
                email=f'hod.{code.lower()}@dec.edu',
                defaults={
                    'first_name': first,
                    'last_name': last,
                    'role': 'hod',
                    'college': college,
                    'is_active': True,
                    'is_approved': True,
                    'password': hashed_pwd,
                }
            )
            users[f'hod_{code}'] = hod
            
            # Create Staff Profile for HOD
            StaffProfile.objects.get_or_create(
                user=hod,
                defaults={
                    'college': college,
                    'employee_id': f'EMP-HOD-{code}',
                    'department': dept,
                    'designation': 'Professor & HOD',
                    'qualification': 'Ph.D. in Engineering',
                    'specialization': f'Advanced {dept.name}',
                    'experience_years': 15,
                    'joining_date': date(2018, 6, 1),
                }
            )

        # Teachers (2 per dept)
        teacher_names = {
            'CE': [('Anjali', 'Desai'), ('Vikram', 'Joshi')],
            'IT': [('Kiran', 'Rao'), ('Rajesh', 'Pillai')],
            'ME': [('Deepak', 'Kumar'), ('Sunil', 'More')],
            'EXTC': [('Jyoti', 'Das'), ('Alok', 'Trivedi')],
            'AIDS': [('Vijay', 'Sen'), ('Komal', 'Pandey')],
            'CIVIL': [('Pranav', 'Mishra'), ('Swati', 'Dave')],
        }
        for code, dept in departments.items():
            for i, (first, last) in enumerate(teacher_names[code], 1):
                t_email = f'teacher.{code.lower()}{i}@dec.edu'
                teacher, _ = User.objects.get_or_create(
                    email=t_email,
                    defaults={
                        'first_name': first,
                        'last_name': last,
                        'role': 'teacher',
                        'college': college,
                        'is_active': True,
                        'is_approved': True,
                        'password': hashed_pwd,
                    }
                )
                users[f'teacher_{code}_{i}'] = teacher

                # Create Staff Profile for Teacher
                StaffProfile.objects.get_or_create(
                    user=teacher,
                    defaults={
                        'college': college,
                        'employee_id': f'EMP-T-{code}-{i}',
                        'department': dept,
                        'designation': 'Assistant Professor' if i == 2 else 'Associate Professor',
                        'qualification': 'M.Tech / Ph.D.',
                        'specialization': f'{dept.name} Core',
                        'experience_years': 5 + i * 2,
                        'joining_date': date(2021, 1, 1),
                    }
                )

        # Lab Assistants
        # CE assistant
        la_ce, _ = User.objects.get_or_create(
            email='labassistant.ce@dec.edu',
            defaults={
                'first_name': 'Nikhil',
                'last_name': 'More',
                'role': 'lab_assistant',
                'college': college,
                'is_active': True,
                'is_approved': True,
                'password': hashed_pwd,
            }
        )
        users['la_ce'] = la_ce
        StaffProfile.objects.get_or_create(
            user=la_ce,
            defaults={
                'college': college,
                'employee_id': 'EMP-LA-CE',
                'department': departments['CE'],
                'designation': 'Senior Lab Assistant',
                'qualification': 'Diploma in Computer Tech',
                'specialization': 'Network & Lab Systems',
                'experience_years': 4,
                'joining_date': date(2022, 6, 1),
            }
        )

        # IT assistant
        la_it, _ = User.objects.get_or_create(
            email='labassistant.it@dec.edu',
            defaults={
                'first_name': 'Rahul',
                'last_name': 'Patil',
                'role': 'lab_assistant',
                'college': college,
                'is_active': True,
                'is_approved': True,
                'password': hashed_pwd,
            }
        )
        users['la_it'] = la_it
        StaffProfile.objects.get_or_create(
            user=la_it,
            defaults={
                'college': college,
                'employee_id': 'EMP-LA-IT',
                'department': departments['IT'],
                'designation': 'Lab Assistant',
                'qualification': 'B.Sc. IT',
                'specialization': 'Database Administration',
                'experience_years': 2,
                'joining_date': date(2023, 7, 15),
            }
        )

        # Multi-department assistant (CE and IT)
        la_multi, _ = User.objects.get_or_create(
            email='labassistant.multi@dec.edu',
            defaults={
                'first_name': 'Sanjay',
                'last_name': 'Vyas',
                'role': 'lab_assistant',
                'college': college,
                'is_active': True,
                'is_approved': True,
                'password': hashed_pwd,
            }
        )
        users['la_multi'] = la_multi
        StaffProfile.objects.get_or_create(
            user=la_multi,
            defaults={
                'college': college,
                'employee_id': 'EMP-LA-MULTI',
                'department': departments['CE'],
                'designation': 'System Specialist Lab Assistant',
                'qualification': 'B.E. Computer Science',
                'specialization': 'Multi-platform Lab Automation',
                'experience_years': 6,
                'joining_date': date(2020, 10, 1),
            }
        )

        self.stdout.write(f'[OK] Seeded Admin, Principal, HODs, Teachers, and Lab Assistants.')
        return users

    def _assign_department_hods(self, departments, users):
        for code, dept in departments.items():
            dept.hod = users[f'hod_{code}']
            dept.save()
        self.stdout.write('[OK] Assigned HOD users to all Departments.')

    def _seed_lab_assistant_rbac(self, users, departments):
        # Bind lab assistants to their departments
        LabAssistantDepartment.objects.get_or_create(user=users['la_ce'], department=departments['CE'], defaults={'is_active': True})
        LabAssistantDepartment.objects.get_or_create(user=users['la_it'], department=departments['IT'], defaults={'is_active': True})
        
        # la_multi is assigned to both CE and IT
        LabAssistantDepartment.objects.get_or_create(user=users['la_multi'], department=departments['CE'], defaults={'is_active': True})
        LabAssistantDepartment.objects.get_or_create(user=users['la_multi'], department=departments['IT'], defaults={'is_active': True})
        
        self.stdout.write('[OK] Bound Lab Assistants to Departments (M2M RBAC Security Seeded).')

    def _seed_divisions(self, college, courses, academic_year, users):
        divisions = []
        div_configs = [
            # Course, Name, Year, Coordinator
            ('CE', 'A', 2, users['teacher_CE_1']),
            ('CE', 'B', 2, users['teacher_CE_2']),
            ('CE', 'A', 3, users['teacher_CE_1']),
            ('IT', 'A', 2, users['teacher_IT_1']),
            ('IT', 'A', 3, users['teacher_IT_2']),
            ('ME', 'A', 2, users['teacher_ME_1']),
            ('ME', 'A', 3, users['teacher_ME_2']),
            ('EXTC', 'A', 2, users['teacher_EXTC_1']),
            ('AIDS', 'A', 2, users['teacher_AIDS_1']),
        ]
        for c_code, name, year, coord in div_configs:
            div, _ = Division.objects.get_or_create(
                course=courses[c_code],
                academic_year=academic_year,
                name=name,
                year_of_study=year,
                defaults={
                    'college': college,
                    'capacity': 60,
                    'class_coordinator': coord,
                    'is_active': True,
                }
            )
            divisions.append(div)
        self.stdout.write(f'[OK] Seeded {len(divisions)} academic divisions.')
        return divisions

    def _seed_subjects(self, college, departments, courses):
        subject_configs = [
            # Name, Code, Dept, Course, YearOfStudy, Sem, Credits, IsLab
            ('Data Structures', 'DS301', 'CE', 'CE', 2, 3, 4, False),
            ('Database Management Systems', 'DB302', 'CE', 'CE', 2, 3, 4, False),
            ('Data Structures Laboratory', 'DS301L', 'CE', 'CE', 2, 3, 2, True),
            ('Database Management Systems Lab', 'DB302L', 'CE', 'CE', 2, 3, 2, True),
            ('Computer Networks', 'CN501', 'CE', 'CE', 3, 5, 4, False),
            
            ('Web Programming', 'WP301', 'IT', 'IT', 2, 3, 4, False),
            ('Software Engineering & Design', 'SE302', 'IT', 'IT', 2, 3, 4, False),
            ('Web Programming Laboratory', 'WP301L', 'IT', 'IT', 2, 3, 2, True),
            
            ('Thermodynamics', 'TD301', 'ME', 'ME', 2, 3, 4, False),
            ('Fluid Mechanics', 'FM302', 'ME', 'ME', 2, 3, 4, False),
            ('Fluid Mechanics Laboratory', 'FM302L', 'ME', 'ME', 2, 3, 2, True),
            
            ('Signals & Systems', 'SS301', 'EXTC', 'EXTC', 2, 3, 4, False),
            ('Analog Electronics Circuit', 'AE302', 'EXTC', 'EXTC', 2, 3, 4, False),
            
            ('Introduction to Artificial Intelligence', 'AI301', 'AIDS', 'AIDS', 2, 3, 4, False),
            ('Python for Data Science', 'PY302', 'AIDS', 'AIDS', 2, 3, 4, False),
            ('Data Science Practical Lab', 'DS302L', 'AIDS', 'AIDS', 2, 3, 2, True),
        ]
        subjects = []
        for name, code, d_code, c_code, year, sem, credits, is_lab in subject_configs:
            subj, _ = Subject.objects.get_or_create(
                college=college,
                code=code,
                defaults={
                    'department': departments[d_code],
                    'course': courses[c_code],
                    'name': name,
                    'year_of_study': year,
                    'semester': sem,
                    'credits': credits,
                    'is_lab': is_lab,
                    'is_active': True,
                }
            )
            subjects.append(subj)
        self.stdout.write(f'[OK] Seeded {len(subjects)} Subjects (Theory & Practical Labs).')
        return subjects

    def _seed_virtual_rooms(self, college, created_by, departments):
        rooms_data = [
            # Name, Building, Dept_Code, Floor, Capacity, Lat, Lng
            ('Advanced Computing Lab', 'Newton Block', 'CE', 3, 45, 18.5204, 73.8567),
            ('DBMS Research Lab', 'Newton Block', 'CE', 3, 40, 18.5205, 73.8568),
            ('Web Technologies Lab', 'Newton Block', 'IT', 2, 50, 18.5210, 73.8570),
            ('Thermal Fluid Mechanics Lab', 'Tesla Block', 'ME', 1, 40, 18.5195, 73.8560),
            ('Embedded Systems Lab', 'Edison Block', 'EXTC', 2, 35, 18.5215, 73.8580),
            ('AI Innovation & Deep Learning Hub', 'Newton Block', 'AIDS', 4, 60, 18.5220, 73.8585),
            ('Main Seminar Hall', 'Admin Block', 'CE', 1, 150, 18.5200, 73.8565),
        ]
        rooms = []
        for name, bld, dept_code, floor, cap, lat, lng in rooms_data:
            room, _ = VirtualRoom.objects.get_or_create(
                college=college,
                name=name,
                defaults={
                    'building': bld,
                    'department': departments[dept_code].name, # String field
                    'floor_number': floor,
                    'capacity': cap,
                    'center_lat': lat,
                    'center_lng': lng,
                    'is_active': True,
                    'created_by': created_by,
                }
            )
            
            # Seed exactly 4 bounding corners for geofence validation has_polygon
            offsets = [(-0.0001, -0.0001), (0.0001, -0.0001), (0.0001, 0.0001), (-0.0001, 0.0001)]
            for idx, (lat_off, lng_off) in enumerate(offsets):
                RoomCorner.objects.get_or_create(
                    room=room,
                    corner_index=idx,
                    defaults={
                        'latitude': lat + lat_off,
                        'longitude': lng + lng_off,
                        'altitude': 20.0,
                        'heading': 0.0,
                        'accuracy': 2.0,
                        'accuracy_meters': 1.5,
                    }
                )
            rooms.append(room)
        self.stdout.write(f'[OK] Seeded {len(rooms)} Geofenced Labs/Classrooms (with corners).')
        return rooms

    def _seed_subject_allocations(self, college, subjects, divisions, academic_year, users):
        allocations = []
        
        # We match subject courses with divisions courses to allocate them properly
        for subj in subjects:
            matching_divs = [d for d in divisions if d.course == subj.course and d.year_of_study == subj.year_of_study]
            for div in matching_divs:
                # Assign to teacher 1 or 2 based on dept
                dept_code = subj.department.code
                teacher = users[f'teacher_{dept_code}_1'] if 'Laboratory' not in subj.name else users[f'teacher_{dept_code}_2']
                
                alloc, _ = SubjectAllocation.objects.get_or_create(
                    subject=subj,
                    teacher=teacher,
                    division=div,
                    academic_year=academic_year,
                    defaults={
                        'college': college,
                        'is_active': True,
                    }
                )
                allocations.append(alloc)
        self.stdout.write(f'[OK] Allocated {len(allocations)} Subjects to Faculty teachers.')
        return allocations

    def _seed_timetable_grid(self, college, divisions, allocations):
        timetable_records = []
        days_of_week = [1, 2, 3, 4, 5]  # Mon to Fri
        start_times = [time(9, 0), time(10, 15), time(11, 30), time(13, 30)]
        end_times = [time(10, 15), time(11, 30), time(12, 45), time(14, 45)]

        for div in divisions:
            div_allocs = [a for a in allocations if a.division == div]
            if not div_allocs:
                continue
            for day in days_of_week:
                # Seed 2 slot mappings per day to make timetables highly realistic
                for slot_idx in range(2):
                    alloc = random.choice(div_allocs)
                    tt, _ = Timetable.objects.get_or_create(
                        college=college,
                        division=div,
                        subject_allocation=alloc,
                        day_of_week=day,
                        start_time=start_times[slot_idx],
                        end_time=end_times[slot_idx],
                        defaults={
                            'room_number': f'Room-{random.randint(100, 400)}',
                            'effective_from': date(2024, 6, 15),
                            'effective_to': date(2024, 11, 30),
                            'is_active': True,
                        }
                    )
                    timetable_records.append(tt)
        self.stdout.write(f'[OK] Seeded {len(timetable_records)} Timetable entries.')

    def _seed_students_bulk(self, college, divisions, courses, academic_year, students_count):
        self.stdout.write(f'Registering {students_count} students in bulk...')
        
        first_names = [
            'Rahul', 'Priya', 'Amit', 'Sneha', 'Rohan', 'Anjali', 'Vikram', 'Divya', 'Sandeep', 'Neha', 
            'Aditya', 'Pooja', 'Abhishek', 'Kiran', 'Suresh', 'Meera', 'Rajesh', 'Shruti', 'Deepak', 'Nisha', 
            'Sunil', 'Jyoti', 'Vijay', 'Aarushi', 'Arjun', 'Tanvi', 'Manoj', 'Kavita', 'Sanjay', 'Ritu', 
            'Pranav', 'Payal', 'Harish', 'Swati', 'Alok', 'Rashmi', 'Ganesh', 'Prachi', 'Vinay', 'Komal',
            'Manish', 'Neha', 'Sachin', 'Sonali', 'Yash', 'Riddhi', 'Kunal', 'Ishita', 'Arvind', 'Shreya'
        ]
        last_names = [
            'Sharma', 'Patil', 'Kulkarni', 'Joshi', 'Desai', 'More', 'Verma', 'Gupta', 'Singh', 'Kumar', 
            'Mehta', 'Shah', 'Nair', 'Pillai', 'Rao', 'Reddy', 'Choudhury', 'Sen', 'Banerjee', 'Chatterjee', 
            'Das', 'Roy', 'Bose', 'Mishra', 'Pandey', 'Trivedi', 'Vyas', 'Shastri', 'Dave', 'Chavan',
            'Sinha', 'Kapoor', 'Malhotra', 'Bhasin', 'Grover', 'Dhillon', 'Gill', 'Jha', 'Pathak', 'Dubey'
        ]

        users_to_create = []
        student_configs = []
        hashed_pwd = make_password('Admin@123')

        # We will distribute students evenly across active divisions
        for idx in range(students_count):
            first = random.choice(first_names)
            last = random.choice(last_names)
            email = f'stud.{first.lower()}.{last.lower()}.{idx+1000}@dec.edu'
            prn = f'PRN2024{idx+1000:04d}'
            roll_number = f'{(idx % 50) + 1:02d}'
            
            user = User(
                id=uuid.uuid4(),
                email=email,
                first_name=first,
                last_name=last,
                phone=f'98{random.randint(10, 99)}45{random.randint(100, 999)}',
                role='student',
                college=college,
                is_active=True,
                is_approved=True,
                password=hashed_pwd,
            )
            users_to_create.append(user)

            # Map division configuration
            div = divisions[idx % len(divisions)]
            student_configs.append({
                'user': user,
                'prn': prn,
                'roll_number': roll_number,
                'division': div,
                'course': div.course,
                'academic_year': academic_year,
                'year_of_study': div.year_of_study,
            })

        # Bulk create Users
        User.objects.bulk_create(users_to_create)
        
        # Load the saved users back to build profiles
        db_users = {u.email: u for u in User.objects.filter(role='student', college=college)}
        
        profiles_to_create = []
        for config in student_configs:
            saved_user = db_users[config['user'].email]
            profile = StudentProfile(
                user=saved_user,
                college=college,
                division=config['division'],
                course=config['course'],
                academic_year=config['academic_year'],
                prn=config['prn'],
                roll_number=config['roll_number'],
                year_of_study=config['year_of_study'],
                approval_status='APPROVED',
                is_active=True,
                face_registered=True, # Pre-register face embeddings
            )
            profiles_to_create.append(profile)

        StudentProfile.objects.bulk_create(profiles_to_create)
        self.stdout.write(f'[OK] Seeded {students_count} Student accounts & profiles in database.')
        return StudentProfile.objects.filter(college=college)

    def _seed_student_enrollments_and_biometrics(self, student_profiles, allocations, academic_year):
        enrollments = []
        face_descriptors = []
        face_images = []
        devices = []

        self.stdout.write('Generating subject enrollments and biometrics for all students...')
        for idx, profile in enumerate(student_profiles):
            # Select subject allocations matching the student's division
            div_allocs = [a for a in allocations if a.division == profile.division]
            for alloc in div_allocs:
                enrollments.append(StudentSubjectEnrollment(
                    student=profile,
                    subject_allocation=alloc,
                    academic_year=academic_year,
                    is_active=True,
                ))

            # DeepFace / ML Kit 128-float embedding
            fake_embedding = [random.uniform(-0.12, 0.12) for _ in range(128)]
            face_descriptors.append(FaceDescriptor(
                student=profile,
                embedding=fake_embedding,
                model_used='DeepFace-FaceNet',
                registered_by=profile.college.users.filter(role='college_admin').first(),
            ))

            # Bounding images
            face_images.append(FaceRegistrationImage(
                student=profile,
                image_path=f'https://images.unsplash.com/photo-{1500000000000 + idx}?auto=format&fit=crop&q=80&w=200',
                angle='front',
            ))

            # Registered devices
            devices.append(DeviceRegistry(
                user=profile.user,
                device_id=f'DEV{idx+5000:06d}',
                device_name='Samsung Galaxy A32' if idx % 2 == 0 else 'OnePlus Nord CE 3',
                platform='android',
                is_active=True,
                is_verified=True,
            ))

        StudentSubjectEnrollment.objects.bulk_create(enrollments)
        FaceDescriptor.objects.bulk_create(face_descriptors)
        FaceRegistrationImage.objects.bulk_create(face_images)
        DeviceRegistry.objects.bulk_create(devices)
        
        # Link device id directly to student users
        for idx, profile in enumerate(student_profiles):
            profile.user.device_id = f'dev{idx+5000:06d}'
            profile.user.save(update_fields=['device_id'])

        self.stdout.write(f'[OK] Enrolled students in {len(enrollments)} subjects and initialized bio-embeddings.')

    def _seed_historical_attendance(self, college, allocations, student_profiles, rooms):
        self.stdout.write('Seeding historical 30-day attendance timeline (Ended sessions & logs)...')
        
        # Timeline: 30 days in the past
        sessions_to_create = []
        logs_to_create = []
        
        # Let's seed 15 historical sessions per allocation to create solid trend graphs
        today = date.today()
        session_codes = set()
        
        # Pre-assign targets to students based on roll numbers to test filters & defaulter logic cleanly:
        # Toppers (divisible by 10): 95% target presence
        # Regulars (rem 1 to 7): 82% target presence
        # Defaulters (rem 8, 9): 48% target presence
        student_targets = {}
        for s in student_profiles:
            rem = int(s.roll_number) % 10
            if rem == 0:
                student_targets[s.user.id] = 95
            elif rem in (8, 9):
                student_targets[s.user.id] = 48
            else:
                student_targets[s.user.id] = 82

        for alloc in allocations:
            # Get students enrolled in this subject allocation
            enrolled_students = [p for p in student_profiles if p.division == alloc.division]
            if not enrolled_students:
                continue

            for day_offset in range(1, 20):  # 20 historical sessions per allocation
                sess_date = today - timedelta(days=day_offset)
                if sess_date.weekday() == 6:  # Skip Sundays
                    continue

                # Session code
                while True:
                    code = ''.join(random.choices(string.ascii_uppercase + string.digits, k=6))
                    if code not in session_codes:
                        session_codes.add(code)
                        break

                start_dt = datetime.combine(sess_date, time(9 + (day_offset % 4), 0))
                end_dt = start_dt + timedelta(hours=1)
                
                # Pick virtual room (geofence)
                room = next((r for r in rooms if r.department == alloc.subject.department.name), rooms[0])

                sess = AttendanceSession(
                    id=uuid.uuid4(),
                    college=college,
                    subject_allocation=alloc,
                    virtual_room=room,
                    teacher=alloc.teacher,
                    session_code=code,
                    status='ended',
                    scheduled_start=start_dt,
                    scheduled_end=end_dt,
                    actual_start=start_dt,
                    actual_end=end_dt,
                    total_students=len(enrolled_students),
                )
                sessions_to_create.append(sess)

                # Generate logs
                present_in_sess = 0
                for stud in enrolled_students:
                    target = student_targets[stud.user.id]
                    is_present = random.randint(1, 100) <= target
                    
                    status = 'present' if is_present else 'absent'
                    if is_present:
                        present_in_sess += 1

                    logs_to_create.append(AttendanceLog(
                        session=sess,
                        student=stud.user,
                        college=college,
                        status=status,
                        marked_at=start_dt + timedelta(minutes=random.randint(1, 12)),
                        marked_lat=room.center_lat,
                        marked_lng=room.center_lng,
                        is_verified_gps=is_present,
                        is_verified_face=is_present,
                        gps_accuracy=2.5 if is_present else 0.0,
                        face_confidence=0.92 if is_present else 0.0,
                    ))
                
                sess.present_count = present_in_sess

        # Bulk create sessions and logs
        AttendanceSession.objects.bulk_create(sessions_to_create)
        
        # Save logs (chunked to avoid postgres limits)
        chunk_size = 5000
        for i in range(0, len(logs_to_create), chunk_size):
            AttendanceLog.objects.bulk_create(logs_to_create[i:i+chunk_size])

        self.stdout.write(f'[OK] Seeded {len(sessions_to_create)} ended historical sessions and {len(logs_to_create)} attendance logs successfully.')

    def _seed_notifications_and_notices(self, college, users, departments):
        notifs = []
        admin_user = users['admin']
        
        # High priority notice board alerts
        notice = NoticeBoard.objects.create(
            college=college,
            title='End-Semester Attendance Requirements',
            content='All students are strictly reminded that maintaining a minimum of 75% attendance per subject is mandatory to appear for final practical and theory examinations. Shortages will be reported directly to HODs.',
            created_by=admin_user,
            publish_at=timezone.now(),
            expires_at=timezone.now() + timedelta(days=30),
            is_active=True,
        )
        notice.target_departments.add(departments['CE'], departments['IT'])

        # Dynamic low attendance alerts for active students
        student_users = User.objects.filter(role='student', college=college)[:10]
        for s in student_users:
            notifs.append(Notification(
                college=college,
                recipient=s,
                sender=admin_user,
                title='Low Attendance Alert',
                message='Your average attendance in Computer Networks (CN501) has fallen below 75%. Please contact your class coordinator immediately.',
                notif_type='attendance',
                is_read=False,
            ))
            
        Notification.objects.bulk_create(notifs)
        self.stdout.write(f'[OK] Seeded notice boards and notifications.')

    def _seed_audit_logs(self, college, users):
        audits = []
        action_samples = [
            ('auth.login', 'User', 'Success'),
            ('attendance.create', 'AttendanceSession', 'Created session code CN501'),
            ('virtual_room.create', 'VirtualRoom', 'Registered geofence Room-301'),
            ('student.approve', 'StudentProfile', 'Approved student registration'),
        ]
        
        for i in range(40):
            act, r_type, desc = random.choice(action_samples)
            audits.append(AuditLog(
                college=college,
                user=users['admin'],
                action=act,
                resource_type=r_type,
                resource_id=str(uuid.uuid4()),
                ip_address='192.168.1.100',
                device_id='DEV-AUDIT-999',
                response_status=200,
            ))
        AuditLog.objects.bulk_create(audits)
        self.stdout.write(f'[OK] Seeded system operations audit trail logs.')

    def _print_production_summary(self, college, users, departments, students_count):
        self.stdout.write('\n' + '=' * 60)
        self.stdout.write(self.style.SUCCESS('ERP DATABASE SEEDING COMPLETED SUCCESSFULLY'))
        self.stdout.write('=' * 60)
        self.stdout.write(f'College             : {college.name} ({college.code})')
        self.stdout.write(f'Domain              : {college.email_domain}')
        self.stdout.write(f'Academic Departments: {len(departments)} successfully integrated')
        self.stdout.write(f'Registered Students : {students_count} active profiles')
        self.stdout.write(f'Historical Sessions : 30 days timeline queryable')
        self.stdout.write('')
        self.stdout.write('TEST LOGIN CREDENTIALS:')
        self.stdout.write('-' * 60)
        creds = [
            ('Super Admin', 'superadmin@platform.com', 'Admin@123', 'Manage all systems'),
            ('College Admin', 'admin@dec.edu', 'Admin@123', 'Manage college academics'),
            ('Principal', 'principal@dec.edu', 'Admin@123', 'View college-wide reports'),
            ('HOD (Comp Eng)', 'hod.ce@dec.edu', 'Admin@123', 'Scoped department stats'),
            ('Teacher (Comp Eng)', 'teacher.ce1@dec.edu', 'Admin@123', 'Mark attendance / create sessions'),
            ('Lab Assis (Comp Eng)', 'labassistant.ce@dec.edu', 'Admin@123', 'Single department scoped'),
            ('Lab Assis (Multi-Dept)', 'labassistant.multi@dec.edu', 'Admin@123', 'CS + IT dynamic RBAC scoped'),
        ]
        for role, email, pwd, scope in creds:
            self.stdout.write(f'{role:<22} | {email:<32} | {pwd:<10} | {scope}')
        self.stdout.write('=' * 60 + '\n')
