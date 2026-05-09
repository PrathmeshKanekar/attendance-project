from django.urls import path
from .views import (
    AttendanceSummaryView,
    DefaultersView,
    DownloadPDFView,
    DownloadExcelView,
    StudentMyAttendanceView,
    TeacherSessionHistoryView,
    CollegeOverviewView,
    DashboardSummaryView,
    AttendanceTrendsView,
)

urlpatterns = [
    path('attendance-summary/',       AttendanceSummaryView.as_view(),    name='report-summary'),
    path('defaulters/',               DefaultersView.as_view(),           name='report-defaulters'),
    path('download/pdf/',             DownloadPDFView.as_view(),          name='report-pdf'),
    path('download/excel/',           DownloadExcelView.as_view(),        name='report-excel'),
    path('student/my-attendance/',    StudentMyAttendanceView.as_view(),  name='student-report'),
    path('teacher/session-history/',  TeacherSessionHistoryView.as_view(),name='teacher-history'),
    path('college/overview/',         CollegeOverviewView.as_view(),      name='college-overview'),
    
    # New analytical endpoints
    path('summary/',                  DashboardSummaryView.as_view(),     name='report-dashboard-summary'),
    path('trends/',                   AttendanceTrendsView.as_view(),      name='report-trends'),
]
