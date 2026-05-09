
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/repositories/i_report_repository.dart';
import '../../data/repositories/report_repository_impl.dart';
import '../cubit/reports_cubit.dart';
import '../widgets/analytics_card.dart';
import '../widgets/attendance_line_chart.dart';
import '../widgets/report_data_table.dart';

class ReportsDashboardPage extends ConsumerWidget {
  const ReportsDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(apiClientProvider);
    final repository = ReportRepositoryImpl(api);

    return BlocProvider(
      create: (context) => ReportsCubit(repository)..loadDashboard(),
      child: const _ReportsView(),
    );
  }
}

class _ReportsView extends StatelessWidget {
  const _ReportsView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        title: const Text('Enterprise Reports'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list_rounded),
            onPressed: () => _showFilters(context),
          ),
          IconButton(
            icon: const Icon(Icons.file_download_rounded),
            onPressed: () => _showExportOptions(context),
          ),
        ],
      ),
      body: BlocBuilder<ReportsCubit, ReportsState>(
        builder: (context, state) {
          if (state is ReportsLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is ReportsError) {
            return Center(child: Text(state.message, style: const TextStyle(color: AppColors.danger)));
          }
          if (state is ReportsLoaded) {
            return _buildContent(context, state);
          }
          return const SizedBox();
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, ReportsLoaded state) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary Grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1.5,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: state.summaries.length,
            itemBuilder: (context, index) => AnalyticsCard(summary: state.summaries[index]),
          ),
          
          const SizedBox(height: 24),
          
          // Trends Chart
          const Text(
            'Attendance Trends (Last 7 Days)',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          AttendanceLineChart(data: state.trends),
          
          const SizedBox(height: 32),
          
          // Detailed Report Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Detailed Reports',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              TextButton.icon(
                onPressed: () => context.read<ReportsCubit>().loadDetailedReport(state.activeType),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ReportDataTable(data: state.detailedData),
        ],
      ),
    );
  }

  void _showFilters(BuildContext context) {
    // Implementation for dynamic filters bottom sheet
  }

  void _showExportOptions(BuildContext context) {
    // Implementation for export dialog (PDF, Excel, CSV)
  }
}
