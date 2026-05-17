import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/layout/app_layout.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/api_client.dart';

class AcademicManagementScreen extends ConsumerWidget {
  const AcademicManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppLayout(
      title: 'Academic Structure',
      child: DefaultTabController(
        length: 4,
        child: Column(
          children: [
            const TabBar(
              isScrollable: true,
              labelColor: AppColors.primaryLight,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primaryLight,
              tabs: [
                Tab(text: 'Departments'),
                Tab(text: 'Courses'),
                Tab(text: 'Divisions'),
                Tab(text: 'Subjects'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _ManagementList(type: 'departments'),
                  _ManagementList(type: 'courses'),
                  _ManagementList(type: 'divisions'),
                  _ManagementList(type: 'subjects'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final academicByTypeListProvider = FutureProvider.family<List, String>((ref, type) async {
  final api = ref.read(apiClientProvider);
  final res = await api.get('/api/academic/$type/');
  return res.data as List;
});

class _ManagementList extends ConsumerWidget {
  final String type;
  const _ManagementList({required this.type});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(academicByTypeListProvider(type));

    return listAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (items) => ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final item = items[i];
          return Card(
            child: ListTile(
              title: Text(item['name'] ?? item['code'] ?? 'Unnamed'),
              subtitle: Text(item['description'] ?? item['code'] ?? ''),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            ),
          );
        },
      ),
    );
  }
}
