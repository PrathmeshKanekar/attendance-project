from django.urls import path
from .views import (
    DepartmentListCreateView, DepartmentDetailView,
    CourseListCreateView, CourseDetailView,
    AcademicYearListCreateView, AcademicYearDetailView, SetCurrentAcademicYearView,
    DivisionListCreateView, DivisionDetailView,
    SubjectListCreateView, SubjectDetailView,
    SubjectAllocationListCreateView, SubjectAllocationDetailView,
    MyAllocationsView,
    BulkEnrollView, EnrollmentListView,
    StudentsListView,
)

urlpatterns = [
    # Departments
    path('departments/',         DepartmentListCreateView.as_view(), name='dept-list-create'),
    path('departments/<uuid:pk>/', DepartmentDetailView.as_view(),   name='dept-detail'),

    # Courses
    path('courses/',             CourseListCreateView.as_view(), name='course-list-create'),
    path('courses/<uuid:pk>/',   CourseDetailView.as_view(),    name='course-detail'),

    # Academic Years
    path('academic-years/',      AcademicYearListCreateView.as_view(), name='year-list-create'),
    path('academic-years/<uuid:pk>/', AcademicYearDetailView.as_view(), name='year-detail'),
    path('academic-years/<uuid:pk>/set-current/',
         SetCurrentAcademicYearView.as_view(), name='year-set-current'),

    # Divisions
    path('divisions/',           DivisionListCreateView.as_view(), name='div-list-create'),
    path('divisions/<uuid:pk>/', DivisionDetailView.as_view(),    name='div-detail'),

    # Subjects
    path('subjects/',            SubjectListCreateView.as_view(), name='subj-list-create'),
    path('subjects/<uuid:pk>/',  SubjectDetailView.as_view(),    name='subj-detail'),

    # Allocations
    path('allocations/',         SubjectAllocationListCreateView.as_view(), name='alloc-list-create'),
    path('allocations/<uuid:pk>/', SubjectAllocationDetailView.as_view(),   name='alloc-detail'),
    path('allocations/my/',      MyAllocationsView.as_view(), name='my-allocations'),

    # Enrollments
    path('enrollments/bulk/',    BulkEnrollView.as_view(),      name='enroll-bulk'),
    path('enrollments/',         EnrollmentListView.as_view(),  name='enroll-list'),

    # Students list (for pickers)
    path('students/',            StudentsListView.as_view(),    name='students-list'),
]
