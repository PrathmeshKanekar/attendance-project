import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class AppErrorWidget extends StatelessWidget {
  final String       message;
  final VoidCallback onRetry;

  const AppErrorWidget({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child  : Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size : 56,
              color: AppColors.warning,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style    : const TextStyle(
                color  : AppColors.textSecondary,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon     : const Icon(Icons.refresh_rounded),
              label    : const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
