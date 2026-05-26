import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';

class PendingApprovalScreen extends StatelessWidget {
  final String status; // 'pending', 'rejected', 'blocked'
  final String message;

  const PendingApprovalScreen({
    super.key,
    required this.status,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width > 800;

    IconData statusIcon;
    Color statusColor;
    String statusTitle;
    String statusDescription;

    if (status == 'rejected') {
      statusIcon = Icons.cancel_rounded;
      statusColor = AppColors.danger;
      statusTitle = 'Registration Rejected';
      statusDescription = message.isNotEmpty
          ? message
          : 'Your registration was rejected by the Lab Assistant. Please check the details and register again.';
    } else if (status == 'blocked') {
      statusIcon = Icons.block_rounded;
      statusColor = AppColors.danger;
      statusTitle = 'Account Blocked';
      statusDescription = message.isNotEmpty
          ? message
          : 'Your account has been suspended/blocked due to security compliance violations. Please contact the head of department.';
    } else {
      statusIcon = Icons.pending_actions_rounded;
      statusColor = AppColors.warning;
      statusTitle = 'Awaiting Approval';
      statusDescription = 'Your profile registration has been submitted successfully.\n\nLab Assistants of your department are currently verifying your face biometrics and academic credentials. You will be able to log in once approved.';
    }

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 550),
            padding: const EdgeInsets.all(32.0),
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                )
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animated Status Circle
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    statusIcon,
                    color: statusColor,
                    size: 48,
                  ),
                ),
                const SizedBox(height: 24),

                // Status Title
                Text(
                  statusTitle,
                  style: TextStyle(
                    fontSize: isDesktop ? 24 : 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                // Status Description
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  decoration: BoxDecoration(
                    color: AppColors.bgSecondary,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.borderColor),
                  ),
                  child: Text(
                    statusDescription,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 32),

                // Helpful Guidelines
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'What happens next?',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _buildStepItem(
                  '1',
                  'Details Verification',
                  'Lab assistants cross-match your PRN number and registered subjects with official rolls.',
                ),
                const SizedBox(height: 10),
                _buildStepItem(
                  '2',
                  'Biometric Face ID Scan',
                  'Verification that registration image features match baseline biometric guidelines.',
                ),
                const SizedBox(height: 10),
                _buildStepItem(
                  '3',
                  'Access Provisioned',
                  'An automated secure JWT is issued, activating your real-time geofenced attendance tracking.',
                ),
                const SizedBox(height: 32),

                // Primary Action Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => context.go('/login'),
                    child: const Text(
                      'Return to Login',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepItem(String number, String title, String subtitle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            color: AppColors.primaryLight,
            shape: BoxShape.circle,
          ),
          alignment: CenterPlaygroundAlign.center,
          child: Text(
            number,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.3,
                ),
              ),
            ],
          ),
        )
      ],
    );
  }
}

// Center align helper
class CenterPlaygroundAlign extends Alignment {
  const CenterPlaygroundAlign(super.x, super.y);
  static const Alignment center = Alignment(0.0, 0.0);
}
