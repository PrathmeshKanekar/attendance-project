import pytest
from django.contrib.auth import get_user_model
from rest_framework.test import APIClient
from apps.tenants.models import College
from apps.students.models import StudentProfile
from apps.academic.models import AcademicYear, Division, Course, Department

User = get_user_model()

@pytest.fixture
def api_client():
    return APIClient()

@pytest.fixture
def create_college():
    return College.objects.create(
        name="Test College",
        code="TEST",
        email_domain="test.edu",
        address="123 Test St",
        phone="1234567890",
        is_active=True
    )

@pytest.fixture
def create_principal(create_college):
    return User.objects.create_user(
        email="principal@test.edu",
        password="password123",
        role="principal",
        first_name="Test",
        last_name="Principal",
        college=create_college,
        is_active=True,
        is_approved=True
    )

@pytest.fixture
def create_student(create_college):
    u = User.objects.create_user(
        email="student@test.edu",
        password="password123",
        role="student",
        first_name="Test",
        last_name="Student",
        college=create_college,
        is_active=True,
        is_approved=True
    )
    dept = Department.objects.create(college=create_college, name="IT", code="IT")
    course = Course.objects.create(college=create_college, department=dept, name="B.Tech", code="BTECH")
    ay = AcademicYear.objects.create(college=create_college, name="2024-25", start_date="2024-06-01", end_date="2025-05-31", is_current=True)
    div = Division.objects.create(college=create_college, course=course, academic_year=ay, name="A", year_of_study=1)
    sp = StudentProfile.objects.create(
        user=u,
        college=create_college,
        division=div,
        course=course,
        academic_year=ay,
        prn="PRN123456",
        roll_number="1",
        year_of_study=1
    )
    return u, sp

@pytest.mark.django_db
def test_login_email_success(api_client, create_principal):
    response = api_client.post('/api/auth/login/email/', {
        "email": "principal@test.edu",
        "password": "password123"
    })
    assert response.status_code == 200
    assert "access" in response.data
    assert "user" in response.data
    assert response.data["user"]["role"] == "principal"

@pytest.mark.django_db
def test_login_email_unapproved(api_client, create_college):
    u = User.objects.create_user(
        email="unapproved@test.edu",
        password="password123",
        role="teacher",
        college=create_college,
        is_active=True,
        is_approved=False
    )
    response = api_client.post('/api/auth/login/email/', {
        "email": "unapproved@test.edu",
        "password": "password123"
    })
    assert response.status_code == 403
    assert "pending approval" in response.data["error"].lower()

@pytest.mark.django_db
def test_login_email_wrong_password(api_client, create_principal):
    response = api_client.post('/api/auth/login/email/', {
        "email": "principal@test.edu",
        "password": "wrongpassword"
    })
    assert response.status_code == 401

@pytest.mark.django_db
def test_login_prn_success(api_client, create_student):
    user, sp = create_student
    response = api_client.post('/api/auth/login/prn/', {
        "prn": "PRN123456",
        "password": "password123"
    })
    assert response.status_code == 200
    assert "access" in response.data
    assert response.data["user"]["prn"] == "PRN123456"

@pytest.mark.django_db
def test_auth_me(api_client, create_principal):
    api_client.force_authenticate(user=create_principal)
    response = api_client.get('/api/auth/me/')
    assert response.status_code == 200
    assert "user" in response.data
    assert response.data["user"]["email"] == create_principal.email

@pytest.mark.django_db
def test_create_user_blocked_roles_no_principal(api_client, create_college):
    college_admin = User.objects.create_user(
        email="admin@test.edu",
        password="password123",
        role="college_admin",
        college=create_college,
        is_active=True,
        is_approved=True
    )
    api_client.force_authenticate(user=college_admin)
    response = api_client.post('/api/users/', {
        "email": "new_teacher@test.edu",
        "role": "teacher",
        "first_name": "New",
        "last_name": "Teacher"
    })
    assert response.status_code == 403
    assert "principal must be created" in response.data["error"].lower()

@pytest.mark.django_db
def test_device_register(api_client, create_principal):
    api_client.force_authenticate(user=create_principal)
    response = api_client.post('/api/auth/register-device/', {
        "device_id": "device_xyz_123",
        "device_name": "iPhone 15",
        "platform": "ios"
    })
    assert response.status_code == 200
    create_principal.refresh_from_db()
    assert create_principal.device_id == "device_xyz_123"
