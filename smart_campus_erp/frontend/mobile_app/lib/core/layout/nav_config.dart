import 'package:flutter/material.dart';
import 'nav_item.dart';

class NavConfig {
  NavConfig._();

  static List<NavItem> getItems(String role) {
    switch (role) {

      case 'super_admin':
        return const [
          NavItem(
            label : 'Dashboard',
            icon  : Icons.dashboard_rounded,
            route : '/super-admin/dashboard',
          ),
          NavItem(
            label : 'Colleges',
            icon  : Icons.school_rounded,
            route : '/super-admin/colleges',
          ),
          NavItem(
            label : 'All Users',
            icon  : Icons.people_rounded,
            route : '/super-admin/users',
          ),
          NavItem(
            label : 'Reports',
            icon  : Icons.analytics_rounded,
            route : '/super-admin/reports',
          ),
          NavItem(
            label : 'Audit Logs',
            icon  : Icons.history_rounded,
            route : '/super-admin/audit',
          ),
        ];

      case 'college_admin':
        return const [
          NavItem(
            label : 'Dashboard',
            icon  : Icons.dashboard_rounded,
            route : '/admin/dashboard',
          ),
          NavItem(
            label : 'Academic Years',
            icon  : Icons.calendar_today_rounded,
            route : '/admin/academic-years',
          ),
          NavItem(
            label : 'Departments',
            icon  : Icons.apartment_rounded,
            route : '/admin/departments',
          ),
          NavItem(
            label : 'Courses',
            icon  : Icons.school_rounded,
            route : '/admin/courses',
          ),
          NavItem(
            label : 'Add Users',
            icon  : Icons.person_add_rounded,
            route : '/admin/users/add',
          ),
        ];

      case 'lab_assistant':
        return const [
          NavItem(
            label : 'Dashboard',
            icon  : Icons.dashboard_rounded,
            route : '/admin/dashboard',
          ),
          NavItem(
            label : 'Virtual Rooms',
            icon  : Icons.sensor_door_rounded,
            route : '/admin/virtual-rooms',
          ),
          NavItem(
            label : 'Subjects',
            icon  : Icons.menu_book_rounded,
            route : '/admin/subjects',
          ),
          NavItem(
            label : 'Divisions',
            icon  : Icons.groups_rounded,
            route : '/admin/divisions',
          ),
          NavItem(
            label : 'Allocations',
            icon  : Icons.assignment_rounded,
            route : '/admin/allocations',
          ),
          NavItem(
            label : 'Enrollments',
            icon  : Icons.how_to_reg_rounded,
            route : '/admin/enrollments',
          ),
          NavItem(
            label : 'Face Register',
            icon  : Icons.face_retouching_natural_rounded,
            route : '/admin/face-register',
          ),
          NavItem(
            label : 'Approvals',
            icon  : Icons.check_circle_rounded,
            route : '/admin/approvals',
          ),
        ];

      case 'principal':
        return const [
          NavItem(
            label : 'Dashboard',
            icon  : Icons.dashboard_rounded,
            route : '/principal/dashboard',
          ),
          NavItem(
            label : 'Approvals',
            icon  : Icons.check_circle_rounded,
            route : '/principal/approvals',
          ),
          NavItem(
            label : 'Attendance',
            icon  : Icons.bar_chart_rounded,
            route : '/principal/attendance',
          ),
          NavItem(
            label : 'Defaulters',
            icon  : Icons.warning_amber_rounded,
            route : '/principal/defaulters',
          ),
          NavItem(
            label : 'Reports',
            icon  : Icons.analytics_rounded,
            route : '/principal/reports',
          ),
        ];

      case 'hod':
        return const [
          NavItem(
            label : 'Dashboard',
            icon  : Icons.dashboard_rounded,
            route : '/hod/dashboard',
          ),
          NavItem(
            label : 'Dept Report',
            icon  : Icons.pie_chart_rounded,
            route : '/hod/reports',
          ),
          NavItem(
            label : 'Faculty',
            icon  : Icons.person_search_rounded,
            route : '/hod/faculty',
          ),
          NavItem(
            label : 'Defaulters',
            icon  : Icons.warning_amber_rounded,
            route : '/hod/defaulters',
          ),
          NavItem(
            label : 'Subjects',
            icon  : Icons.menu_book_rounded,
            route : '/hod/subjects',
          ),
        ];

      case 'teacher':
        return const [
          NavItem(
            label : 'Dashboard',
            icon  : Icons.dashboard_rounded,
            route : '/teacher/dashboard',
          ),
          NavItem(
            label : 'My Sessions',
            icon  : Icons.play_circle_rounded,
            route : '/teacher/sessions',
          ),
          NavItem(
            label : 'Attendance',
            icon  : Icons.fact_check_rounded,
            route : '/teacher/attendance',
          ),
          NavItem(
            label : 'Reports',
            icon  : Icons.analytics_rounded,
            route : '/teacher/reports',
          ),
          NavItem(
            label : 'Manual Entry',
            icon  : Icons.edit_note_rounded,
            route : '/teacher/manual',
          ),
        ];

      case 'student':
        return const [
          NavItem(
            label : 'Dashboard',
            icon  : Icons.dashboard_rounded,
            route : '/student/dashboard',
          ),
          NavItem(
            label : 'Mark Attendance',
            icon  : Icons.fact_check_rounded,
            route : '/student/mark-attendance',
          ),
          NavItem(
            label : 'My Subjects',
            icon  : Icons.menu_book_rounded,
            route : '/student/subjects',
          ),
          NavItem(
            label : 'My Report',
            icon  : Icons.analytics_rounded,
            route : '/student/report',
          ),
          NavItem(
            label : 'Notifications',
            icon  : Icons.notifications_rounded,
            route : '/student/notifications',
          ),
        ];

      default:
        return const [];
    }
  }

  /// Returns color chip for each role — used in sidebar user card
  static Color roleColor(String role) {
    switch (role) {
      case 'super_admin'   : return const Color(0xFF7C3AED);
      case 'college_admin' : return const Color(0xFF0F766E);
      case 'principal'     : return const Color(0xFF1D4ED8);
      case 'hod'           : return const Color(0xFF0369A1);
      case 'teacher'       : return const Color(0xFF15803D);
      case 'student'       : return const Color(0xFFB45309);
      case 'lab_assistant' : return const Color(0xFFBE185D);
      default              : return const Color(0xFF475569);
    }
  }

  /// Human-readable role label
  static String roleLabel(String role) {
    switch (role) {
      case 'super_admin'   : return 'Super Admin';
      case 'college_admin' : return 'College Admin';
      case 'principal'     : return 'Principal';
      case 'hod'           : return 'HOD';
      case 'teacher'       : return 'Teacher';
      case 'student'       : return 'Student';
      case 'lab_assistant' : return 'Lab Assistant';
      default              : return role;
    }
  }
}
