import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/layout/app_layout.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/loading_widget.dart';
import '../../core/widgets/error_widget.dart';
import '../../core/widgets/empty_state_widget.dart';
import 'face_register_provider.dart';

class FaceRegisterListScreen extends ConsumerStatefulWidget {
  const FaceRegisterListScreen({super.key});

  @override
  ConsumerState<FaceRegisterListScreen> createState() =>
      _FaceRegisterListScreenState();
}

class _FaceRegisterListScreenState
    extends ConsumerState<FaceRegisterListScreen> {
  String _search       = '';
  String _filterStatus = 'all'; // all / registered / pending

  @override
  Widget build(BuildContext context) {
    final asyncData = ref.watch(faceListProvider);

    return AppLayout(
      title  : 'Face Registration',
      actions: [
        IconButton(
          icon     : const Icon(Icons.refresh_rounded),
          onPressed: () => ref.invalidate(faceListProvider),
          tooltip  : 'Refresh',
        ),
      ],
      child: asyncData.when(
        loading: () => const LoadingWidget(message: 'Loading students...'),
        error  : (e, _) => AppErrorWidget(
          message: e.toString(),
          onRetry: () => ref.invalidate(faceListProvider),
        ),
        data   : (data) {
          final students  = List<Map<String, dynamic>>.from(
            data['students'] as List,
          );
          final total       = data['total']            as int? ?? 0;
          final registered  = data['registered_count'] as int? ?? 0;
          final pending     = data['pending_count']    as int? ?? 0;

          // Apply local filters
          var filtered = students.where((s) {
            final matchSearch = _search.isEmpty
                || s['name'].toString().toLowerCase().contains(_search.toLowerCase())
                || s['prn'].toString().toLowerCase().contains(_search.toLowerCase());
            final matchStatus = _filterStatus == 'all'
                || (_filterStatus == 'registered' && s['face_registered'] == true)
                || (_filterStatus == 'pending'    && s['face_registered'] == false);
            return matchSearch && matchStatus;
          }).toList();

          return Column(
            children: [

              // ── Summary bar ──────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 14,
                ),
                color: AppColors.bgSecondary,
                child: Row(
                  children: [
                    _SummaryChip(
                      label: 'Total',
                      value: '$total',
                      color: AppColors.primaryLight,
                    ),
                    const SizedBox(width: 10),
                    _SummaryChip(
                      label: 'Registered',
                      value: '$registered',
                      color: AppColors.success,
                    ),
                    const SizedBox(width: 10),
                    _SummaryChip(
                      label: 'Pending',
                      value: '$pending',
                      color: AppColors.warning,
                    ),
                  ],
                ),
              ),

              // ── Search + filter ──────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child  : Column(
                  children: [
                    // Search box
                    TextField(
                      decoration: const InputDecoration(
                        hintText   : 'Search by name or PRN...',
                        prefixIcon : Icon(Icons.search_rounded),
                      ),
                      onChanged: (v) => setState(() => _search = v),
                    ),
                    const SizedBox(height: 10),
                    // Filter chips
                    Row(
                      children: [
                        _FilterChip(
                          label    : 'All',
                          selected : _filterStatus == 'all',
                          onTap    : () => setState(() => _filterStatus = 'all'),
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label    : 'Registered ✓',
                          selected : _filterStatus == 'registered',
                          color    : AppColors.success,
                          onTap    : () => setState(
                            () => _filterStatus = 'registered',
                          ),
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label    : 'Pending',
                          selected : _filterStatus == 'pending',
                          color    : AppColors.warning,
                          onTap    : () => setState(
                            () => _filterStatus = 'pending',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // ── Student list ─────────────────────────────
              Expanded(
                child: filtered.isEmpty
                    ? const EmptyStateWidget(
                        message : 'No students found',
                        icon    : Icons.people_outline_rounded,
                      )
                    : ListView.separated(
                        padding        : const EdgeInsets.all(16),
                        itemCount      : filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder    : (context, i) {
                          final s = filtered[i];
                          return _StudentFaceCard(
                            student: s,
                            onRegister: () => context.push(
                              '/admin/face-register/camera',
                              extra: s,
                            ),
                            onDelete: () =>
                                _confirmDelete(context, ref, s),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    WidgetRef    ref,
    Map<String, dynamic> student,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title  : const Text('Remove Face Registration'),
        shape  : RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        content: Text(
          'Remove face registration for ${student['name']}? '
          'They will need to be re-registered before marking attendance.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child    : const Text('Cancel'),
          ),
          ElevatedButton(
            style    : ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              minimumSize    : const Size(90, 44),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref
                  .read(faceRegisterProvider.notifier)
                  .deleteFace(student['student_id'].toString());
              ref.invalidate(faceListProvider);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content        : Text('Face registration removed.'),
                    backgroundColor: AppColors.success,
                  ),
                );
              }
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}


// ── Student face card ──────────────────────────────────────
class _StudentFaceCard extends StatelessWidget {
  final Map<String, dynamic> student;
  final VoidCallback         onRegister;
  final VoidCallback         onDelete;

  const _StudentFaceCard({
    required this.student,
    required this.onRegister,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isRegistered = student['face_registered'] == true;

    return Container(
      padding   : const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color       : AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border      : Border(
          left: BorderSide(
            color: isRegistered ? AppColors.success : AppColors.warning,
            width: 4,
          ),
          top   : const BorderSide(color: AppColors.borderColor),
          right : const BorderSide(color: AppColors.borderColor),
          bottom: const BorderSide(color: AppColors.borderColor),
        ),
      ),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius         : 24,
            backgroundColor: isRegistered
                ? AppColors.success.withOpacity(0.12)
                : AppColors.warning.withOpacity(0.12),
            child: Icon(
              isRegistered ? Icons.face_rounded : Icons.face_outlined,
              color: isRegistered ? AppColors.success : AppColors.warning,
              size : 28,
            ),
          ),

          const SizedBox(width: 14),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  student['name']?.toString() ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize  : 15,
                    color     : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'PRN: ${student['prn']}  ·  Roll: ${student['roll_number']}',
                  style: const TextStyle(
                    color  : AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 5),
                // Status chip
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color       : isRegistered
                        ? AppColors.success.withOpacity(0.10)
                        : AppColors.warning.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isRegistered
                        ? '✓ Face Registered'
                        : '⚠ Not Registered',
                    style: TextStyle(
                      color    : isRegistered
                          ? AppColors.success
                          : AppColors.warning,
                      fontSize : 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (isRegistered && student['registered_at'] != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Registered by: ${student['registered_by'] ?? "Unknown"}',
                    style: const TextStyle(
                      color  : AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Action buttons
          Column(
            children: [
              IconButton(
                icon     : Icon(
                  isRegistered
                      ? Icons.refresh_rounded
                      : Icons.add_a_photo_rounded,
                  color: AppColors.primaryLight,
                  size : 22,
                ),
                onPressed: onRegister,
                tooltip  : isRegistered ? 'Re-register Face' : 'Register Face',
              ),
              if (isRegistered)
                IconButton(
                  icon     : const Icon(
                    Icons.delete_outline_rounded,
                    color: AppColors.danger,
                    size : 22,
                  ),
                  onPressed: onDelete,
                  tooltip  : 'Remove Registration',
                ),
            ],
          ),
        ],
      ),
    );
  }
}


// ── Helper widgets ─────────────────────────────────────────
class _SummaryChip extends StatelessWidget {
  final String label, value;
  final Color  color;
  const _SummaryChip({
    required this.label,
    required this.value,
    required this.color,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding   : const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color       : color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
        border      : Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(
            color: color, fontSize: 20, fontWeight: FontWeight.w800,
          )),
          Text(label, style: TextStyle(
            color: color.withOpacity(0.80), fontSize: 11,
          )),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool   selected;
  final Color  color;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color = AppColors.primaryLight,
  });
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap : onTap,
      child : AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding : const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color       : selected ? color : AppColors.bgSecondary,
          borderRadius: BorderRadius.circular(20),
          border      : Border.all(
            color: selected ? color : AppColors.borderColor,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color     : selected ? Colors.white : AppColors.textSecondary,
            fontSize  : 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
