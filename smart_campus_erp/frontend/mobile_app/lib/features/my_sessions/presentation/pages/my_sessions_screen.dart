
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/layout/app_layout.dart';
import '../../../../core/widgets/error_widget.dart';
import '../../../../core/widgets/loading_widget.dart';
import '../cubit/sessions_cubit.dart';
import '../cubit/sessions_state.dart';
import '../providers/session_repository_provider.dart';
import '../widgets/teacher_session_card.dart';

import '../widgets/start_session_sheet.dart';

class MySessionsScreen extends ConsumerWidget {
  const MySessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(sessionRepositoryProvider);

    return BlocProvider(
      create: (context) => SessionsCubit(repository)..loadSessions(),
      child: const _SessionsView(),
    );
  }
}

class _SessionsView extends StatelessWidget {
  const _SessionsView();

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title: 'My Sessions',
      fab: FloatingActionButton.extended(
        onPressed: () => _showStartSessionSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('New Session'),
        backgroundColor: AppColors.success,
      ),
      child: Column(
        children: [
          // Filter Bar
          const _FilterBar(),
          
          Expanded(
            child: BlocBuilder<SessionsCubit, SessionsState>(
              builder: (context, state) {
                if (state is SessionsLoading) {
                  return const LoadingWidget(message: 'Fetching your sessions...');
                }
                
                if (state is SessionsError) {
                  return AppErrorWidget(
                    message: state.message,
                    onRetry: () => context.read<SessionsCubit>().loadSessions(),
                  );
                }
                
                if (state is SessionsLoaded) {
                  if (state.sessions.isEmpty) {
                    return const _EmptySessions();
                  }
                  
                  return RefreshIndicator(
                    onRefresh: () => context.read<SessionsCubit>().loadSessions(silent: true),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: state.sessions.length,
                      itemBuilder: (context, index) {
                        final session = state.sessions[index];
                        return TeacherSessionCard(
                          session: session,
                          onEnd: () => _confirmEndSession(context, session.id),
                          onViewDetails: () {}, // Navigate to details
                        );
                      },
                    ),
                  );
                }
                
                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showStartSessionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const StartSessionSheet(),
    ).then((_) {
      if (context.mounted) {
        context.read<SessionsCubit>().loadSessions(silent: true);
      }
    });
  }

  void _confirmEndSession(BuildContext context, String id) {
    showDialog(
      context: context,
      builder: (dContext) => AlertDialog(
        title: const Text('End Session?'),
        content: const Text('This will stop all further attendance marking for this session.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dContext), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              context.read<SessionsCubit>().endSession(id);
              Navigator.pop(dContext);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('End Session'),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: AppColors.cardBg,
        border: Border(bottom: BorderSide(color: AppColors.borderColor)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const _FilterChip(label: 'All', status: null),
            const SizedBox(width: 8),
            const _FilterChip(label: 'Active', status: 'active'),
            const SizedBox(width: 8),
            const _FilterChip(label: 'Scheduled', status: 'scheduled'),
            const SizedBox(width: 8),
            const _FilterChip(label: 'Completed', status: 'completed'),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final String? status;

  const _FilterChip({required this.label, required this.status});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SessionsCubit, SessionsState>(
      builder: (context, state) {
        final isSelected = state is SessionsLoaded && state.filterStatus == status;
        
        return FilterChip(
          label: Text(label),
          selected: isSelected,
          onSelected: (_) => context.read<SessionsCubit>().loadSessions(status: status),
          selectedColor: AppColors.primaryLight.withOpacity(0.2),
          checkmarkColor: AppColors.primaryLight,
          labelStyle: TextStyle(
            color: isSelected ? AppColors.primaryLight : AppColors.textSecondary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        );
      },
    );
  }
}

class _EmptySessions extends StatelessWidget {
  const _EmptySessions();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_note_rounded, size: 80, color: AppColors.textSecondary.withOpacity(0.2)),
          const SizedBox(height: 16),
          const Text(
            'No sessions found',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 8),
          const Text(
            'Create a new session to start tracking attendance.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
