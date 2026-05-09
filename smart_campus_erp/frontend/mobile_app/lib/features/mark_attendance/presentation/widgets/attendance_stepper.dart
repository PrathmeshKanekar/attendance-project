
import 'package:flutter/material.dart';
import '../cubit/attendance_state.dart';
import '../../../../core/constants/app_colors.dart';

class AttendanceStepper extends StatelessWidget {
  final AttendanceStep currentStep;
  final Map<AttendanceStep, StepStatus> statuses;

  const AttendanceStepper({
    super.key,
    required this.currentStep,
    required this.statuses,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _buildDot(AttendanceStep.sessionCheck),
        _buildLine(AttendanceStep.sessionCheck),
        _buildDot(AttendanceStep.gpsValidation),
        _buildLine(AttendanceStep.gpsValidation),
        _buildDot(AttendanceStep.livenessDetection),
        _buildLine(AttendanceStep.livenessDetection),
        _buildDot(AttendanceStep.faceMatch),
      ],
    );
  }

  Widget _buildDot(AttendanceStep step) {
    final status = statuses[step] ?? StepStatus.pending;
    final bool isCurrent = currentStep == step;
    
    Color color;
    if (status == StepStatus.success) {
      color = AppColors.success;
    } else if (isCurrent) {
      color = AppColors.primaryLight;
    } else {
      color = Colors.white12;
    }

    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: isCurrent ? [
          BoxShadow(color: color.withOpacity(0.5), blurRadius: 8, spreadRadius: 2),
        ] : null,
      ),
    );
  }

  Widget _buildLine(AttendanceStep step) {
    final status = statuses[step] ?? StepStatus.pending;
    final bool isPassed = status == StepStatus.success;

    return Expanded(
      child: Container(
        height: 2,
        color: isPassed ? AppColors.success.withOpacity(0.5) : Colors.white10,
      ),
    );
  }
}
