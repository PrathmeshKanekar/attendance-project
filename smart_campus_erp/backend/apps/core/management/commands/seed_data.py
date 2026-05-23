import uuid
import random
import sys
from datetime import date, timedelta, datetime, time
from django.core.management.base import BaseCommand
from django.db import transaction
from django.utils import timezone
from django.contrib.auth.hashers import make_password
from faker import Faker

from apps.tenants.models import College
from apps.accounts.models import User, DeviceRegistry, normalize_device_id
from apps.academic.models import (
    Department, Course, AcademicYear, Semester, Division, Subject, SubjectAllocation
)
from apps.students.models import StudentProfile, StudentSubjectEnrollment
from apps.staff.models import StaffProfile
from apps.approvals.models import ApprovalRequest
from apps.virtual_rooms.models import VirtualRoom, RoomCorner
from apps.attendance.models import AttendanceSession, AttendanceLog, ManualAttendanceRequest
from apps.face_recognition.models import FaceDescriptor, FaceRegistrationImage
from apps.notifications.models import Notification


class Command(BaseCommand):
    help = 'Seed production-quality multi-college test data for dashboards, reports, and RBAC testing.'

    def add_arguments(self, parser):
        parser.add_argument('--reset', action='store_true', help='Wipe all data before seeding')
        parser.add_argument('--students', type=int, default=300, help='Total students across all colleges')
        parser.add_argument('--days', type=int, default=15, help='Days of attendance history')

    def log(self, msg):
        self.stdout.write(msg)
        self.stdout.flush()

    def handle(self, *args, **options):
        if options['reset']:
            self._reset_data()
        try:
            with transaction.atomic():
                self._seed(options['students'], options['days'])
        except Exception as e:
            self.log(self.style.ERROR(f"FAILED: {e}"))
            import traceback; traceback.print_exc()
            return
        self.log(self.style.SUCCESS("\nDatabase seeding completed successfully!"))

    def _reset_data(self):
        self.log("Resetting database...")
        from apps.reports.models import GeneratedReport
        from apps.audit.models import AuditLog
        from django.db import connection
        
        # Drop legacy tables that hold stale constraints to accounts_user
        with connection.cursor() as cursor:
            cursor.execute("SELECT table_name FROM information_schema.tables WHERE table_schema='public'")
            tables = [row[0] for row in cursor.fetchall()]
            if 'virtual_rooms_roomcorner' in tables:
                self.log("Dropping legacy table virtual_rooms_roomcorner...")
                cursor.execute("DROP TABLE virtual_rooms_roomcorner CASCADE")
            if 'virtual_rooms_virtualroom' in tables:
                self.log("Dropping legacy table virtual_rooms_virtualroom...")
                cursor.execute("DROP TABLE virtual_rooms_virtualroom CASCADE")

        ManualAttendanceRequest.objects.all().delete()
        AttendanceLog.objects.all().delete()
        AttendanceSession.objects.all().delete()
        RoomCorner.objects.all().delete()
        # NULL out user FK before deleting rooms/users
        VirtualRoom.objects.all().update(created_by=None)
        VirtualRoom.objects.all().delete()
        FaceDescriptor.objects.all().delete()
        FaceRegistrationImage.objects.all().delete()
        StudentSubjectEnrollment.objects.all().delete()
        StudentProfile.objects.all().delete()
        StaffProfile.objects.all().delete()
        ApprovalRequest.objects.all().delete()
        DeviceRegistry.objects.all().delete()
        Notification.objects.all().delete()
        GeneratedReport.objects.all().delete()
        AuditLog.objects.all().delete()
        SubjectAllocation.objects.all().delete()
        Subject.objects.all().delete()
        # NULL out coordinator FK before deleting divisions/users
        Division.objects.all().update(class_coordinator=None)
        Division.objects.all().delete()
        Semester.objects.all().delete()
        AcademicYear.objects.all().delete()
        Course.objects.all().delete()
        # NULL out HOD FK before deleting departments/users
        Department.objects.all().update(hod=None)
        Department.objects.all().delete()
        User.objects.exclude(email='superadmin@app.com').delete()
        College.objects.all().delete()
        self.log(self.style.SUCCESS("Reset complete."))

    def _seed(self, total_students, history_days):
        fake = Faker('en_IN')
        pw = make_password('password123')

        # ── 1. Super Admin ──
        self.log("1/13 Super Admin...")
        sa, created = User.objects.get_or_create(
            email='superadmin@app.com',
            defaults=dict(first_name='System', last_name='SuperAdmin', role='super_admin',
                          is_active=True, is_approved=True, is_staff=True, is_superuser=True, password=pw))
        if not created:
            sa.password = pw; sa.save()

        # ── 2. Colleges ──
        self.log("2/13 Colleges...")
        college_cfgs = [
            ('Imperial College of Engineering', 'ICE', 'ice.edu', '411005', 18.5204, 73.8567),
            ('Trinity College of Technology',   'TCT', 'tct.edu', '400051', 19.0760, 72.8777),
            ('Apex Polytechnic Institute',      'API', 'api.edu', '400001', 18.9696, 72.8230),
        ]
        colleges = []
        for name, code, domain, pin, lat, lng in college_cfgs:
            c = College.objects.create(name=name, code=code, email_domain=domain,
                                       address=f'{fake.street_address()}, {pin}',
                                       phone=fake.phone_number()[:20], is_active=True)
            c._lat, c._lng = lat, lng          # transient attrs for room coords
            colleges.append(c)

        # ── 3. Admins & Principals ──
        self.log("3/13 Admins & Principals...")
        principals = {}
        approval_objs = []
        for c in colleges:
            User.objects.create(email=f'admin@{c.email_domain}', first_name=fake.first_name(),
                                last_name=fake.last_name(), role='college_admin', college=c,
                                is_active=True, is_approved=True, password=pw)
            p = User.objects.create(email=f'principal@{c.email_domain}', first_name=f'Dr. {fake.first_name()}',
                                    last_name=fake.last_name(), role='principal', college=c,
                                    is_active=True, is_approved=True, password=pw)
            principals[c.id] = p
            approval_objs.append(ApprovalRequest(college=c, user=p, requested_role='principal',
                                                  status='approved', reviewed_by=sa, reviewed_at=timezone.now()))

        # ── 4. Departments ──
        self.log("4/13 Departments...")
        dept_names = [('Computer Engineering','CO'),('Information Technology','IT'),
                      ('Mechanical Engineering','ME'),('Civil Engineering','CE'),('Electronics Engineering','EE')]
        depts = {}  # {college_id: [dept, ...]}
        for c in colleges:
            depts[c.id] = []
            for dn, dc in dept_names:
                d = Department.objects.create(college=c, name=dn, code=dc, is_active=True)
                depts[c.id].append(d)

        # ── 5. Courses ──
        self.log("5/13 Courses...")
        course_cfgs = [('BTech', 'BTECH', 4), ('Diploma', 'DIP', 3)]
        courses = {}  # {college_id: [course, ...]}
        for c in colleges:
            courses[c.id] = []
            for dept in depts[c.id]:
                for cn, cc, dur in course_cfgs:
                    co = Course.objects.create(college=c, department=dept,
                                               name=f'{cn} {dept.name}', code=f'{cc}-{dept.code}',
                                               duration_years=dur, is_active=True)
                    courses[c.id].append(co)

        # ── 6. Academic Year & Semesters ──
        self.log("6/13 Academic Year...")
        ayears = {}
        for c in colleges:
            ay = AcademicYear.objects.create(college=c, name='2025-26',
                                             start_date=date(2025,6,1), end_date=date(2026,5,31), is_current=True)
            ayears[c.id] = ay
            for co in courses[c.id]:
                for yr in range(1, co.duration_years+1):
                    Semester.objects.create(college=c, course=co, academic_year=ay,
                                            semester_number=yr*2-1, start_date=date(2025,6,15),
                                            end_date=date(2025,11,30), is_active=True)

        # ── 7. Divisions (Year 2 & 3, Div A/B) ──
        self.log("7/13 Divisions...")
        divs = {}  # {college_id: [div, ...]}
        for c in colleges:
            divs[c.id] = []
            for co in courses[c.id]:
                for yr in [2, 3]:
                    if yr > co.duration_years: continue
                    for dn in ['A', 'B']:
                        dv = Division.objects.create(college=c, course=co, academic_year=ayears[c.id],
                                                      name=dn, year_of_study=yr, capacity=60, is_active=True)
                        divs[c.id].append(dv)

        # ── 8. Staff: HODs, Teachers, Lab Assistants ──
        self.log("8/13 Staff...")
        staff_profiles = []
        teachers = {}  # {college_id: [user, ...]}
        for c in colleges:
            teachers[c.id] = []
            pri = principals[c.id]
            for dept in depts[c.id]:
                # HOD
                hod = User.objects.create(email=f'hod.{dept.code.lower()}@{c.email_domain}',
                    first_name=fake.first_name(), last_name=fake.last_name(), role='hod',
                    college=c, is_active=True, is_approved=True, password=pw)
                dept.hod = hod; dept.save()
                staff_profiles.append(StaffProfile(user=hod, college=c, employee_id=f'HOD-{c.code}-{dept.code}',
                    department=dept, designation='HOD', qualification='Ph.D',
                    specialization=dept.name, experience_years=15, joining_date=date(2015,1,1)))
                approval_objs.append(ApprovalRequest(college=c, user=hod, requested_role='hod',
                    status='approved', reviewed_by=pri, reviewed_at=timezone.now()))

                # 2 approved teachers + 1 pending
                for idx in range(1, 4):
                    approved = idx <= 2
                    t = User.objects.create(email=f't{idx}.{dept.code.lower()}@{c.email_domain}',
                        first_name=fake.first_name(), last_name=fake.last_name(), role='teacher',
                        college=c, is_active=approved, is_approved=approved, password=pw)
                    staff_profiles.append(StaffProfile(user=t, college=c,
                        employee_id=f'TCH-{c.code}-{dept.code}-{idx}', department=dept,
                        designation='Asst. Professor', qualification='M.Tech',
                        specialization=dept.name, experience_years=random.randint(2,10),
                        joining_date=date(2021,6,1)))
                    if approved: teachers[c.id].append(t)
                    approval_objs.append(ApprovalRequest(college=c, user=t, requested_role='teacher',
                        status='approved' if approved else 'pending',
                        reviewed_by=pri if approved else None,
                        reviewed_at=timezone.now() if approved else None))

                # 1 lab assistant
                la = User.objects.create(email=f'la.{dept.code.lower()}@{c.email_domain}',
                    first_name=fake.first_name(), last_name=fake.last_name(), role='lab_assistant',
                    college=c, is_active=True, is_approved=True, password=pw)
                staff_profiles.append(StaffProfile(user=la, college=c,
                    employee_id=f'LAB-{c.code}-{dept.code}', department=dept,
                    designation='Lab Assistant', qualification='Diploma',
                    specialization='Labs', experience_years=3, joining_date=date(2022,1,1)))
                approval_objs.append(ApprovalRequest(college=c, user=la, requested_role='lab_assistant',
                    status='approved', reviewed_by=pri, reviewed_at=timezone.now()))

        StaffProfile.objects.bulk_create(staff_profiles)
        ApprovalRequest.objects.bulk_create(approval_objs)

        # Assign class coordinators
        for c in colleges:
            tchs = teachers[c.id]
            if not tchs: continue
            for i, dv in enumerate(divs[c.id]):
                dv.class_coordinator = tchs[i % len(tchs)]
                dv.save()
        self.log(f"   {len(staff_profiles)} staff profiles created.")

        # ── 9. Subjects & Allocations ──
        self.log("9/13 Subjects & Allocations...")
        subj_map = {
            'CO': [('DBMS','CS301',2,3),('Operating Systems','CS302',2,4),('Python','CS303',2,3),
                   ('Computer Networks','CS305',3,5),('AI','CS401',3,6)],
            'IT': [('InfoSec','IT301',2,3),('Web Dev','IT302',2,4),('Cloud','IT305',3,5)],
            'ME': [('Thermodynamics','ME301',2,3),('Fluid Mechanics','ME302',2,4)],
            'CE': [('Surveying','CE301',2,3),('Concrete Tech','CE303',2,4)],
            'EE': [('Microcontrollers','EE301',2,3),('DSP','EE302',2,4)],
        }
        allocs = {}  # {college_id: [alloc, ...]}
        # Pre-index: division by (college_id, course_id, year_of_study) -> [div, ...]
        div_index = {}
        for c in colleges:
            allocs[c.id] = []
            for dv in divs[c.id]:
                key = (c.id, dv.course_id, dv.year_of_study)
                div_index.setdefault(key, []).append(dv)

        for c in colleges:
            tchs = teachers[c.id]
            if not tchs: continue
            t_by_dept = {}
            for t in tchs:
                sp = StaffProfile.objects.get(user=t)
                t_by_dept.setdefault(sp.department.code, []).append(t)

            for dept in depts[c.id]:
                slist = subj_map.get(dept.code, [])
                dt = t_by_dept.get(dept.code, [])
                if not dt: continue
                dept_courses = [co for co in courses[c.id] if co.department_id == dept.id]
                for co in dept_courses:
                    for sname, scode, yr, sem in slist:
                        subj = Subject.objects.create(college=c, department=dept, course=co,
                            name=sname, code=f'{scode}-{co.code}', year_of_study=yr,
                            semester=sem, credits=4, is_active=True)
                        matching_divs = div_index.get((c.id, co.id, yr), [])
                        for di, dv in enumerate(matching_divs):
                            teacher = dt[(di + ord(scode[-1])) % len(dt)]
                            al = SubjectAllocation.objects.create(college=c, subject=subj,
                                teacher=teacher, division=dv, academic_year=ayears[c.id], is_active=True)
                            allocs[c.id].append(al)
        self.log(f"   {sum(len(v) for v in allocs.values())} allocations created.")

        # ── 10. Virtual Rooms ──
        self.log("10/13 Virtual Rooms...")
        rooms = {}
        for c in colleges:
            lat, lng = c._lat, c._lng
            pri = principals[c.id]
            r1 = VirtualRoom.objects.create(college=c, name='Lab-A101', building='Main Block',
                department='CS', floor_number=1, capacity=60, center_lat=lat, center_lng=lng, created_by=pri)
            r2 = VirtualRoom.objects.create(college=c, name='Lab-B202', building='Science Wing',
                department='IT', floor_number=2, capacity=60, center_lat=lat+.0003, center_lng=lng+.0003, created_by=pri)
            r3 = VirtualRoom.objects.create(college=c, name='Seminar-Hall', building='Admin Block',
                department='General', floor_number=0, capacity=150, center_lat=lat-.0004, center_lng=lng-.0004, created_by=pri)
            r4 = VirtualRoom.objects.create(college=c, name='Room-301', building='Lecture Block',
                department='ME', floor_number=3, capacity=80, center_lat=lat+.0005, center_lng=lng-.0005, created_by=pri)
            # Polygon corners for Room-301
            for idx, (cl, cg) in enumerate([(lat+.0003,lng-.0007),(lat+.0003,lng-.0003),
                                             (lat+.0007,lng-.0003),(lat+.0007,lng-.0007)]):
                RoomCorner.objects.create(room=r4, corner_index=idx, latitude=cl, longitude=cg)
            rooms[c.id] = [r1, r2, r3, r4]

        # ── 11. Students (bulk) ──
        self.log("11/13 Students...")
        per_college = total_students // len(colleges)
        stu_users, stu_meta = [], []
        for c in colleges:
            cdivs = divs[c.id]
            if not cdivs: continue
            for i in range(1, per_college + 1):
                dv = cdivs[(i-1) % len(cdivs)]
                rand = random.random()
                status = 'APPROVED' if rand < 0.85 else ('PENDING_APPROVAL' if rand < 0.95 else 'REJECTED')
                approved = status == 'APPROVED'
                dev_raw = f'DEVICE-{c.code}-{i:04d}'
                dev_norm = normalize_device_id(dev_raw)
                stu_users.append(User(email=f's{i}.{c.code.lower()}@{c.email_domain}',
                    first_name=fake.first_name(), last_name=fake.last_name(), role='student',
                    college=c, is_active=approved, is_approved=approved, password=pw,
                    device_id=dev_norm if approved else ''))
                stu_meta.append(dict(college=c, div=dv, status=status, approved=approved,
                                     roll=i, dev_norm=dev_norm))

        User.objects.bulk_create(stu_users)
        # Re-fetch to get DB-assigned IDs
        emails = [u.email for u in stu_users]
        db_users = {u.email: u for u in User.objects.filter(email__in=emails)}

        profiles, devs, faces, fimgs, approvals2 = [], [], [], [], []
        for idx, u_obj in enumerate(stu_users):
            m = stu_meta[idx]
            db_u = db_users[u_obj.email]
            c = m['college']
            dv = m['div']
            la = User.objects.filter(college=c, role='lab_assistant').first()

            sp = StudentProfile(user=db_u, college=c, division=dv, course=dv.course,
                academic_year=dv.academic_year,
                prn=f'PRN-{c.code}-{dv.course.code}-{dv.year_of_study}-{m["roll"]:03d}',
                roll_number=str(m['roll']), year_of_study=dv.year_of_study,
                approval_status=m['status'], approved_by=la if m['approved'] else None,
                approved_at=timezone.now() if m['approved'] else None,
                is_active=m['approved'], face_registered=m['approved'])
            profiles.append(sp)

            approvals2.append(ApprovalRequest(college=c, user=db_u, requested_role='student',
                status='approved' if m['status']=='APPROVED' else ('rejected' if m['status']=='REJECTED' else 'pending'),
                reviewed_by=la if m['approved'] else None,
                reviewed_at=timezone.now() if m['approved'] else None))

        StudentProfile.objects.bulk_create(profiles)
        ApprovalRequest.objects.bulk_create(approvals2)

        # Re-fetch profiles for FK references
        db_profiles = {sp.user_id: sp for sp in StudentProfile.objects.filter(user__email__in=emails)}

        for idx, u_obj in enumerate(stu_users):
            m = stu_meta[idx]
            if not m['approved']: continue
            db_u = db_users[u_obj.email]
            sp = db_profiles[db_u.id]
            devs.append(DeviceRegistry(user=db_u, device_id=m['dev_norm'],
                normalized_device_id=m['dev_norm'], device_name='Android Phone',
                platform='android', is_active=True, is_verified=True, last_used_at=timezone.now()))
            faces.append(FaceDescriptor(student=sp,
                embedding=[round(random.uniform(-0.1,0.1),6) for _ in range(128)],
                model_used='DeepFace', registered_by=sa, last_verified_at=timezone.now()))
            fimgs.append(FaceRegistrationImage(student=sp, image_path='/media/faces/mock.jpg', angle='front'))

        DeviceRegistry.objects.bulk_create(devs)
        FaceDescriptor.objects.bulk_create(faces)
        FaceRegistrationImage.objects.bulk_create(fimgs)
        self.log(f"   {len(profiles)} student profiles, {len(devs)} devices, {len(faces)} face profiles.")

        # ── 12. Enrollments (pre-computed, no N+1) ──
        self.log("12/13 Enrollments...")
        # Build division -> [student_user_id] mapping in Python
        div_students = {}  # div_id -> [user_id, ...]
        for sp in profiles:
            if sp.approval_status != 'APPROVED': continue
            div_students.setdefault(sp.division_id, []).append(sp.user_id)

        enrollments = []
        # Also pre-compute: alloc -> [user_id, ...] for attendance generation
        alloc_students = {}
        for c in colleges:
            ay = ayears[c.id]
            for al in allocs[c.id]:
                stu_ids = div_students.get(al.division_id, [])
                alloc_students[al.id] = stu_ids
                for uid in stu_ids:
                    sp = db_profiles.get(uid)
                    if sp:
                        enrollments.append(StudentSubjectEnrollment(
                            student=sp, subject_allocation=al, academic_year=ay, is_active=True))
        StudentSubjectEnrollment.objects.bulk_create(enrollments)
        self.log(f"   {len(enrollments)} enrollments.")

        # ── 13. Attendance Sessions & Logs ──
        self.log("13/13 Attendance history...")
        # Assign permanent attendance probability per student
        stu_prob = {}
        for sp in profiles:
            if sp.approval_status != 'APPROVED': continue
            r = random.random()
            stu_prob[sp.user_id] = (random.uniform(0.90,1.0) if r < 0.60
                                    else random.uniform(0.75,0.89) if r < 0.85
                                    else random.uniform(0.40,0.69))

        end_dt = date.today()
        start_dt = end_dt - timedelta(days=history_days)
        date_list = [start_dt + timedelta(days=i)
                     for i in range((end_dt - start_dt).days + 1)
                     if (start_dt + timedelta(days=i)).weekday() != 6]

        sessions_objs, session_student_map = [], []
        codes_used = set()
        for c in colleges:
            college_allocs = allocs[c.id]
            college_rooms = rooms[c.id]
            if not college_allocs or not college_rooms: continue
            for dt in date_list:
                picked = random.sample(college_allocs, k=min(len(college_allocs), random.randint(3, 5)))
                for al in picked:
                    stu_ids = alloc_students.get(al.id, [])
                    if not stu_ids: continue
                    while True:
                        code = ''.join(random.choices('0123456789', k=6))
                        if code not in codes_used: codes_used.add(code); break
                    room = random.choice(college_rooms)
                    hr = random.randint(9, 15)
                    ss = datetime.combine(dt, time(hr, 0))
                    se = datetime.combine(dt, time(hr+1, 0))
                    sess = AttendanceSession(id=uuid.uuid4(), college=c,
                        subject_allocation=al, virtual_room=room, teacher=al.teacher,
                        session_code=code, status='ended',
                        scheduled_start=timezone.make_aware(ss),
                        scheduled_end=timezone.make_aware(se),
                        actual_start=timezone.make_aware(ss + timedelta(minutes=random.randint(1,5))),
                        actual_end=timezone.make_aware(se),
                        total_students=len(stu_ids),
                        teacher_lat=room.center_lat, teacher_lng=room.center_lng,
                        radius_meters=30.0)
                    sessions_objs.append(sess)
                    session_student_map.append((sess, stu_ids, room, c))

        AttendanceSession.objects.bulk_create(sessions_objs)
        self.log(f"   {len(sessions_objs)} sessions created. Building logs...")

        logs = []
        for sess, stu_ids, room, c in session_student_map:
            present_n = 0
            for uid in stu_ids:
                prob = stu_prob.get(uid, 0.8)
                is_p = random.random() < prob
                if is_p:
                    present_n += 1
                    sr = random.random()
                    st = 'present' if sr < 0.85 else ('late' if sr < 0.95 else 'manual')
                else:
                    st = 'absent'
                logs.append(AttendanceLog(session=sess, student_id=uid, college=c, status=st,
                    marked_lat=room.center_lat + random.uniform(-1e-4,1e-4) if is_p else None,
                    marked_lng=room.center_lng + random.uniform(-1e-4,1e-4) if is_p else None,
                    gps_accuracy=3.5 if is_p else 0, is_verified_gps=is_p, is_verified_face=is_p,
                    device_id='DEVICE-MOCK' if is_p else '',
                    ip_address=f'192.168.1.{random.randint(2,254)}' if is_p else None))
            sess.present_count = present_n

        AttendanceSession.objects.bulk_update(sessions_objs, ['present_count'])
        for i in range(0, len(logs), 2000):
            AttendanceLog.objects.bulk_create(logs[i:i+2000])
        self.log(f"   {len(logs)} attendance logs created.")

        # ── Summary ──
        self.stdout.write('\n' + '='*60)
        self.log(self.style.SUCCESS('SEEDING COMPLETE'))
        self.stdout.write('='*60)
        self.log(f'Colleges       : {len(colleges)}')
        self.log(f'Students       : {total_students}')
        self.log(f'Sessions       : {len(sessions_objs)}')
        self.log(f'Attendance Logs: {len(logs)}')
        self.log(f'\nAll passwords  : password123')
        self.log(f'Super Admin    : superadmin@app.com')
        for c in colleges:
            d = c.email_domain
            self.log(f'\n--- {c.name} ({c.code}) ---')
            self.log(f'  Admin     : admin@{d}')
            self.log(f'  Principal : principal@{d}')
            h = User.objects.filter(college=c, role='hod').first()
            t = User.objects.filter(college=c, role='teacher', is_approved=True).first()
            s = User.objects.filter(college=c, role='student', is_approved=True).first()
            if h: self.log(f'  HOD       : {h.email}')
            if t: self.log(f'  Teacher   : {t.email}')
            if s: self.log(f'  Student   : {s.email}')
        self.stdout.write('='*60 + '\n')
