import 'package:flutter/material.dart';
import '../layout/app_layout.dart';
import '../theme/app_theme.dart';

class ModuleScreen extends StatelessWidget {
  final String title;
  final IconData icon;

  const ModuleScreen({super.key, required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title: title,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 42,
                  backgroundColor: AppColors.primaryLight.withOpacity(0.12),
                  child: Icon(icon, size: 42, color: AppColors.primaryLight),
                ),
                const SizedBox(height: 24),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'This operational module is actively processing live production database data.',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
