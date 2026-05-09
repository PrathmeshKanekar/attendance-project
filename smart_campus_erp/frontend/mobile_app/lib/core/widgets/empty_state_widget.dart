import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class EmptyStateWidget extends StatelessWidget {
  final String   message;
  final IconData icon;
  final String?  subtitle;

  const EmptyStateWidget({
    super.key,
    required this.message,
    required this.icon,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child  : Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign : TextAlign.center,
              style     : const TextStyle(
                fontSize  : 16,
                fontWeight: FontWeight.w600,
                color     : AppColors.textPrimary,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style    : const TextStyle(
                  fontSize: 13,
                  color   : AppColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
