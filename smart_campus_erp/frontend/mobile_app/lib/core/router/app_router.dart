import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../models/user_model.dart';

// Import all screens
import '../../features/splash/splash_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/student/student_dashboard_screen.dart';
import '../../features/mark_attendance/presentation/pages/mark_attendance_page.dart';

import '../../features/student/face_scan_screen.dart';
import '../../features/reports/presentation/pages/reports_dashboard_page.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../network/api_client.dart';
import '../../features/reports/presentation/cubit/reports_cubit.dart';
import '../../features/teacher/teacher_dashboard_screen.dart';
import '../../features/my_sessions/presentation/pages/my_sessions_screen.dart';
import '../../features/teacher/session_logs_screen.dart';
import '../../features/principal/principal_dashboard_screen.dart';
import '../../features/approvals/approvals_screen.dart';
import '../../features/reports/defaulters_screen.dart';
import '../../features/reports/principal_reports_screen.dart';
import '../../features/hod/hod_dashboard_screen.dart';
import '../../features/college_admin/admin_dashboard_screen.dart';
import '../../features/college_admin/manage_users_screen.dart';
import '../../features/college_admin/add_user_screen.dart';
import '../../features/college_admin/user_detail_screen.dart';
import '../../features/college_admin/departments_screen.dart';
import '../../features/college_admin/subjects_screen.dart';
import '../../features/college_admin/divisions_screen.dart';
import '../../features/college_admin/courses_screen.dart';
import '../../features/college_admin/allocations_screen.dart';
import '../../features/college_admin/enrollments_screen.dart';
import '../../features/college_admin/academic_years_screen.dart';
import '../../features/virtual_rooms/virtual_rooms_screen.dart';
import '../../features/virtual_rooms/add_edit_room_screen.dart';
import '../../features/virtual_rooms/room_detail_screen.dart';
import '../../features/virtual_rooms/room_preview_screen.dart';
import '../../features/virtual_rooms/room_validation_screen.dart';
import '../../features/face_register/face_register_list_screen.dart';
import '../../features/face_register/face_register_camera_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/super_admin/super_admin_dashboard_screen.dart';
import '../../features/super_admin/colleges_screen.dart';
import '../../features/auth/registration_screen.dart';
import '../../features/auth/pending_approval_screen.dart';
import '../../features/lab_assistant/lab_approvals_screen.dart';
import '../widgets/coming_soon_screen.dart';

// CRITICAL FIX: router must be kept alive — never recreated
final appRouterProvider = Provider<GoRouter>((ref) {
  ref.keepAlive();

  final notifier = ValueNotifier<AuthState>(AuthInitial());

  ref.listen<AuthState>(authProvider, (_, next) {
    notifier.value = next;
  });

  return GoRouter(
    initialLocation   : '/splash',
    refreshListenable : notifier,
    redirect: (context, state) {
      final isOnRegister = state.matchedLocation == '/register';
      // CRITICAL DIRECT ACCESS RULE: Allow direct access to the registration screen without authentication checks
      if (isOnRegister) {
        return null;
      }

      final auth        = ref.read(authProvider);
      final isOnSplash  = state.matchedLocation == '/splash';
      final isOnLogin   = state.matchedLocation == '/login';
      final isOnPending  = state.matchedLocation == '/pending-approval';

      // If still initializing — go to splash
      if (auth is AuthInitial || auth is AuthLoading) {
        if (!isOnSplash) return '/splash';
        return null;
      }

      // If unauthenticated — allow login, register, and pending approval views
      if (auth is AuthUnauthenticated || auth is AuthError) {
        if (!isOnLogin && !isOnRegister && !isOnPending) return '/login';
        return null;
      }

      // If authenticated and on splash/login/register — redirect to dashboard
      if (auth is AuthSuccess) {
        if (isOnSplash || isOnLogin || isOnRegister) {
          return _dashboardRoute(auth.user);
        }
      }

      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (c, s) => const SplashScreen()),
      GoRoute(path: '/login',  builder: (c, s) => const LoginScreen()),
      GoRoute(path: '/register', builder: (c, s) => const RegistrationScreen()),
      GoRoute(
        path: '/pending-approval',
        builder: (c, s) {
          final query = s.uri.queryParameters;
          return PendingApprovalScreen(
            status: query['status'] ?? 'pending',
            message: query['message'] ?? '',
          );
        },
      ),

      // Student
      GoRoute(path: '/student/dashboard',
          builder: (c, s) => const StudentDashboardScreen()),
      GoRoute(path: '/student/mark-attendance',
          builder: (c, s) {
            final extra = s.extra;
            if (extra == null || extra is! Map<String, dynamic>) {
              return const StudentDashboardScreen();
            }
            return MarkAttendancePage(session: extra);
          }),
      GoRoute(path: '/student/face-scan',
          builder: (c, s) {
            final extra = s.extra;
            if (extra == null || extra is! Map<String, dynamic>) {
              return const StudentDashboardScreen();
            }
            return FaceScanScreen(
              session : extra['session']  as Map<String, dynamic>? ?? {},
              lat     : extra['lat']      as double? ?? 0.0,
              lng     : extra['lng']      as double? ?? 0.0,
              altitude: extra['altitude'] as double? ?? 0.0,
            );
          }),
      GoRoute(path: '/student/subjects',
          builder: (c, s) => const ComingSoonScreen(title: 'My Subjects')),
      GoRoute(path: '/student/report',
          builder: (c, s) => BlocProvider<ReportsCubit>(
                create: (_) => ReportsCubit(ref.read(apiClientProvider)),
                child: const ReportsDashboardPage(),
              )),
      GoRoute(path: '/student/notifications',
          builder: (c, s) => const NotificationsScreen()),

      // Teacher
      GoRoute(path: '/teacher/dashboard',
          builder: (c, s) => const TeacherDashboardScreen()),
      GoRoute(path: '/teacher/sessions',
          builder: (c, s) => const MySessionsScreen()),
      GoRoute(path: '/teacher/attendance',
          builder: (c, s) => BlocProvider<ReportsCubit>(
                create: (_) => ReportsCubit(ref.read(apiClientProvider)),
                child: const ReportsDashboardPage(),
              )),
      GoRoute(path: '/teacher/reports',
          builder: (c, s) => BlocProvider<ReportsCubit>(
                create: (_) => ReportsCubit(ref.read(apiClientProvider)),
                child: const ReportsDashboardPage(),
              )),
      GoRoute(path: '/teacher/manual',
          builder: (c, s) => const ComingSoonScreen(title: 'Manual Entry')),
      GoRoute(path: '/teacher/session-logs',
          builder: (c, s) {
            final extra = s.extra;
            if (extra == null || extra is! Map<String, dynamic>) {
              return const MySessionsScreen();
            }
            return SessionLogsScreen(session: extra);
          }),

      // Principal
      GoRoute(path: '/principal/dashboard',
          builder: (c, s) => const PrincipalDashboardScreen()),
      GoRoute(path: '/principal/approvals',
          builder: (c, s) => const ApprovalsScreen()),
      GoRoute(path: '/principal/attendance',
          builder: (c, s) => BlocProvider<ReportsCubit>(
                create: (_) => ReportsCubit(ref.read(apiClientProvider)),
                child: const ReportsDashboardPage(),
              )),
      GoRoute(path: '/principal/reports',
          builder: (c, s) => BlocProvider<ReportsCubit>(
                create: (_) => ReportsCubit(ref.read(apiClientProvider)),
                child: const ReportsDashboardPage(),
              )),
      GoRoute(path: '/principal/defaulters',
          builder: (c, s) => const DefaultersScreen()),

      // HOD
      GoRoute(path: '/hod/dashboard',
          builder: (c, s) => const HodDashboardScreen()),
      GoRoute(path: '/hod/reports',
          builder: (c, s) => BlocProvider<ReportsCubit>(
                create: (_) => ReportsCubit(ref.read(apiClientProvider)),
                child: const ReportsDashboardPage(),
              )),
      GoRoute(path: '/hod/faculty',
          builder: (c, s) => const ComingSoonScreen(title: 'Faculty')),
      GoRoute(path: '/hod/defaulters',
          builder: (c, s) => const DefaultersScreen()),
      GoRoute(path: '/hod/subjects',
          builder: (c, s) => const ComingSoonScreen(title: 'Subjects')),

      // Admin / Lab Assistant
      GoRoute(path: '/admin/dashboard',
          builder: (c, s) => const AdminDashboardScreen()),
      GoRoute(path: '/admin/users',
          builder: (c, s) => const ManageUsersScreen()),
      GoRoute(path: '/admin/users/add',
          builder: (c, s) => const AddUserScreen()),
      GoRoute(path: '/admin/users/:userId',
          builder: (c, s) =>
              UserDetailScreen(userId: s.pathParameters['userId']!)),
      GoRoute(path: '/admin/departments',
          builder: (c, s) => const DepartmentsScreen()),
      GoRoute(path: '/admin/courses',
          builder: (c, s) => const CoursesScreen()),
      GoRoute(path: '/admin/subjects',
          builder: (c, s) => const SubjectsScreen()),
      GoRoute(path: '/admin/divisions',
          builder: (c, s) => const DivisionsScreen()),
      GoRoute(path: '/admin/virtual-rooms',
          builder: (c, s) => const VirtualRoomsScreen()),
      GoRoute(path: '/admin/virtual-rooms/validate',
          builder: (c, s) => const RoomValidationScreen()),
      GoRoute(path: '/admin/virtual-rooms/add',
          builder: (c, s) => const AddEditRoomScreen()),
      GoRoute(path: '/admin/virtual-rooms/:roomId',
          builder: (c, s) =>
              RoomDetailScreen(roomId: s.pathParameters['roomId']!)),
      GoRoute(path: '/admin/virtual-rooms/:roomId/edit',
          builder: (c, s) => AddEditRoomScreen(
            existingRoom: s.extra as Map<String, dynamic>?,
          )),
      GoRoute(path: '/admin/virtual-rooms/:roomId/preview',
          builder: (c, s) =>
              RoomPreviewScreen(roomId: s.pathParameters['roomId']!)),

      // Non-admin / clean namespace routing for virtual rooms
      GoRoute(path: '/virtual-rooms',
          name: '/virtual-rooms',
          builder: (c, s) => const VirtualRoomsScreen()),
      GoRoute(path: '/virtual-rooms/validate',
          name: '/virtual-rooms/validate',
          builder: (c, s) => const RoomValidationScreen()),
      GoRoute(path: '/virtual-rooms/add',
          name: '/virtual-rooms/add',
          builder: (c, s) => const AddEditRoomScreen()),
      GoRoute(path: '/virtual-rooms/:roomId',
          name: '/virtual-rooms/:roomId',
          builder: (c, s) =>
              RoomDetailScreen(roomId: s.pathParameters['roomId']!)),
      GoRoute(path: '/virtual-rooms/:roomId/preview',
          name: '/virtual-rooms/:roomId/preview',
          builder: (c, s) =>
              RoomPreviewScreen(roomId: s.pathParameters['roomId']!)),
      GoRoute(path: '/virtual-rooms/preview',
          name: '/virtual-rooms/preview',
          builder: (c, s) => const RoomPreviewScreen(roomId: '')),
      GoRoute(path: '/admin/face-register',
          builder: (c, s) => const FaceRegisterListScreen()),
      GoRoute(path: '/admin/face-register/camera',
          builder: (c, s) {
            final extra = s.extra;
            if (extra == null || extra is! Map<String, dynamic>) {
              return const FaceRegisterListScreen();
            }
            return FaceRegisterCameraScreen(student: extra);
          }),
      GoRoute(path: '/admin/reports',
          builder: (c, s) => const PrincipalReportsScreen()),
      GoRoute(path: '/admin/allocations',
          builder: (c, s) => const AllocationsScreen()),
      GoRoute(path: '/admin/enrollments',
          builder: (c, s) => const EnrollmentsScreen()),
      GoRoute(path: '/admin/academic-years',
          builder: (c, s) => const AcademicYearsScreen()),
      GoRoute(path: '/admin/approvals',
          builder: (c, s) => const LabAssistantApprovalsScreen()),

      // Super Admin
      GoRoute(path: '/super-admin/dashboard',
          builder: (c, s) => const SuperAdminDashboardScreen()),
      GoRoute(path: '/super-admin/colleges',
          builder: (c, s) => const CollegesScreen()),
      GoRoute(path: '/super-admin/users',
          builder: (c, s) => const ComingSoonScreen(title: 'All Users')),
      GoRoute(path: '/super-admin/reports',
          builder: (c, s) => const ComingSoonScreen(title: 'Reports')),
      GoRoute(path: '/super-admin/audit',
          builder: (c, s) => const ComingSoonScreen(title: 'Audit Logs')),
    ],
  );
});

String _dashboardRoute(UserModel user) {
  switch (user.role) {
    case 'student':       return '/student/dashboard';
    case 'teacher':       return '/teacher/dashboard';
    case 'principal':     return '/principal/dashboard';
    case 'hod':           return '/hod/dashboard';
    case 'college_admin': return '/admin/dashboard';
    case 'lab_assistant': return '/admin/dashboard';
    case 'super_admin':   return '/super-admin/dashboard';
    default:              return '/login';
  }
}
