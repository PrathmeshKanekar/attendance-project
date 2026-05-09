
import 'package:flutter/material.dart';
import '../cubit/attendance_state.dart';
import '../../../../core/constants/app_colors.dart';

class VerificationStepWidget extends StatelessWidget {
  final String title;
  final String? subtitle;
  final StepStatus status;
  final bool isActive;

  const VerificationStepWidget({
    super.key,
    required this.title,
    this.subtitle,
    required this.status,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isActive ? Colors.white.withOpacity(0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? AppColors.primaryLight.withOpacity(0.3) : Colors.white.withOpacity(0.05),
        ),
      ),
      child: Row(
        children: [
          _buildStatusIcon(),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: isActive ? Colors.white : Colors.white60,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    fontSize: 14,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
              ],
            ),
          ),
          if (status == StepStatus.processing)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryLight),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusIcon() {
    switch (status) {
      case StepStatus.success:
        return const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 22);
      case StepStatus.failed:
        return const Icon(Icons.error_rounded, color: AppColors.danger, size: 22);
      case StepStatus.processing:
        return const Icon(Icons.hourglass_bottom_rounded, color: AppColors.primaryLight, size: 20);
      case StepStatus.pending:
        return const Icon(Icons.radio_button_off_rounded, color: Colors.white24, size: 20);
    }
  }
}
