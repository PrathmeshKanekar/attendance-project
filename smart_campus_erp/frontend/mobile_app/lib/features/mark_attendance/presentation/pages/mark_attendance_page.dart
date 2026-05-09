
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/repositories/i_attendance_repository.dart';
import '../../data/repositories/attendance_repository_impl.dart';
import '../cubit/attendance_cubit.dart';
import '../cubit/attendance_state.dart';
import '../widgets/attendance_stepper.dart';
import '../widgets/verification_step_widget.dart';
import '../widgets/camera_verification_widget.dart';

class MarkAttendancePage extends ConsumerWidget {
  final Map<String, dynamic> session;

  const MarkAttendancePage({super.key, required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(apiClientProvider);
    final repository = AttendanceRepositoryImpl(api);

    return BlocProvider(
      create: (context) => AttendanceCubit(repository)..initSession(session),
      child: const _MarkAttendanceView(),
    );
  }
}

class _MarkAttendanceView extends StatelessWidget {
  const _MarkAttendanceView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: Stack(
        children: [
          // Background Gradient for Futuristic Look
          _buildBackground(),
          
          SafeArea(
            child: Column(
              children: [
                _buildHeader(context),
                Expanded(
                  child: BlocBuilder<AttendanceCubit, AttendanceState>(
                    builder: (context, state) {
                      if (state.currentStep == AttendanceStep.success) {
                        return _buildSuccessView(context);
                      }
                      
                      return _buildMainContent(context, state);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0F172A),
            Color(0xFF1E293B),
            Color(0xFF0F172A),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
            style: IconButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.05)),
          ),
          const SizedBox(width: 16),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AI Verification',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                'Identity & Presence Validation',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent(BuildContext context, AttendanceState state) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          // Step Progress Bar
          AttendanceStepper(currentStep: state.currentStep, statuses: state.stepStatuses),
          const SizedBox(height: 24),
          
          // AI Verification Panel
          if (state.currentStep == AttendanceStep.livenessDetection || 
              state.currentStep == AttendanceStep.faceMatch)
            const CameraVerificationWidget()
          else
            _buildInfoPanel(state),
            
          const SizedBox(height: 24),
          
          // Action/Status List
          _buildStepList(state),
          
          const SizedBox(height: 40),
          
          // Error Message Display
          if (state.errorMessage != null)
            _buildErrorCard(state.errorMessage!),
            
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildInfoPanel(AttendanceState state) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          _infoRow(Icons.subject_rounded, 'Subject', state.sessionData['subject_name'] ?? ''),
          const Divider(height: 32, color: Colors.white10),
          _infoRow(Icons.person_outline_rounded, 'Professor', state.sessionData['teacher_name'] ?? 'TBD'),
          const Divider(height: 32, color: Colors.white10),
          _infoRow(Icons.location_on_outlined, 'Location', state.sessionData['room_name'] ?? 'Virtual Room'),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primaryLight, size: 20),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
            Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
          ],
        ),
      ],
    );
  }

  Widget _buildStepList(AttendanceState state) {
    return Column(
      children: [
        VerificationStepWidget(
          title: 'Session Status',
          status: state.stepStatuses[AttendanceStep.sessionCheck]!,
          isActive: state.currentStep == AttendanceStep.sessionCheck,
        ),
        const SizedBox(height: 12),
        VerificationStepWidget(
          title: 'Device Integrity',
          status: state.stepStatuses[AttendanceStep.deviceSecurity]!,
          isActive: state.currentStep == AttendanceStep.deviceSecurity,
        ),
        const SizedBox(height: 12),
        VerificationStepWidget(
          title: '3D Geo-Boundary',
          status: state.stepStatuses[AttendanceStep.gpsValidation]!,
          isActive: state.currentStep == AttendanceStep.gpsValidation,
          subtitle: state.isInsideRoom ? 'Coordinates Verified' : 'Checking GPS...',
        ),
      ],
    );
  }

  Widget _buildErrorCard(String msg) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.danger.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.danger.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.danger),
          const SizedBox(width: 12),
          Expanded(child: Text(msg, style: const TextStyle(color: AppColors.danger, fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildSuccessView(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 100),
          const SizedBox(height: 24),
          const Text('Attendance Marked!', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Identity & Geo-Presence Verified', style: TextStyle(color: Colors.white60)),
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryLight,
              minimumSize: const Size(200, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Back to Dashboard', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
