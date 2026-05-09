
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../domain/entities/session_entity.dart';

class TeacherSessionCard extends StatelessWidget {
  final SessionEntity session;
  final VoidCallback? onEnd;
  final VoidCallback? onViewDetails;

  const TeacherSessionCard({
    super.key,
    required this.session,
    this.onEnd,
    this.onViewDetails,
  });

  @override
  Widget build(BuildContext context) {
    final bool isLive = session.status == 'active';
    final Color statusColor = _getStatusColor(session.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header Section
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatusIcon(session.status, statusColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              session.subjectName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          _StatusBadge(status: session.status, color: statusColor),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${session.subjectCode} • ${session.divisionName} (Year ${session.yearOfStudy})',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const Divider(height: 1, color: AppColors.borderColor),
          
          // Details Grid
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    _DetailItem(
                      icon: Icons.access_time_rounded,
                      label: 'Time',
                      value: '${DateFormat('HH:mm').format(session.scheduledStart)} - ${DateFormat('HH:mm').format(session.scheduledEnd)}',
                    ),
                    _DetailItem(
                      icon: Icons.room_rounded,
                      label: 'Room',
                      value: session.roomName ?? 'Virtual',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _DetailItem(
                      icon: Icons.people_outline_rounded,
                      label: 'Attendance',
                      value: '${session.presentCount}/${session.totalStudents} Present',
                      valueColor: statusColor,
                    ),
                    _DetailItem(
                      icon: Icons.vpn_key_rounded,
                      label: 'Code',
                      value: session.sessionCode,
                      isCode: true,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Action Section
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.bgPrimary.withOpacity(0.5),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onViewDetails,
                  child: const Text('View Logs'),
                ),
                if (isLive) ...[
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: onEnd,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.danger,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: const Text('End Session'),
                  ),
                ] else if (session.status == 'scheduled') ...[
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {}, // Start Session Logic
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Start Now'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIcon(String status, Color color) {
    IconData icon;
    switch (status) {
      case 'active':
        icon = Icons.sensors_rounded;
        break;
      case 'completed':
        icon = Icons.check_circle_rounded;
        break;
      case 'cancelled':
        icon = Icons.cancel_rounded;
        break;
      default:
        icon = Icons.calendar_today_rounded;
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'active': return AppColors.success;
      case 'completed': return AppColors.primaryLight;
      case 'cancelled': return AppColors.danger;
      case 'expired': return AppColors.warning;
      default: return AppColors.textSecondary;
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  final Color color;

  const _StatusBadge({required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _DetailItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final bool isCode;

  const _DetailItem({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.isCode = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? AppColors.textPrimary,
                    letterSpacing: isCode ? 1.5 : 0,
                    fontFamily: isCode ? 'Monospace' : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
