import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/layout/app_layout.dart';
import '../../core/network/api_client.dart';

final pendingUsersProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final apiClient = ref.read(apiClientProvider);
  final res = await apiClient.get('/api/users/?is_approved=false');
  if (res.data is Map && res.data.containsKey('results')) {
    return List<Map<String, dynamic>>.from(res.data['results']);
  }
  return List<Map<String, dynamic>>.from(res.data);
});

class ApprovalsScreen extends ConsumerWidget {
  const ApprovalsScreen({super.key});

  Future<void> _approveUser(BuildContext context, WidgetRef ref, String id) async {
    final apiClient = ref.read(apiClientProvider);
    try {
      await apiClient.post('/api/users/$id/approve/');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User approved successfully!')));
      }
      ref.invalidate(pendingUsersProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to approve user: $e')));
      }
    }
  }

  Future<void> _rejectUser(BuildContext context, WidgetRef ref, String id, String reason) async {
    final apiClient = ref.read(apiClientProvider);
    try {
      await apiClient.post('/api/users/$id/reject/', data: {'reason': reason});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User rejected.')));
      }
      ref.invalidate(pendingUsersProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to reject user: $e')));
      }
    }
  }

  void _showRejectDialog(BuildContext context, WidgetRef ref, String id) {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Reject User'),
          content: TextField(
            controller: reasonController,
            decoration: const InputDecoration(labelText: 'Reason for Rejection'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () {
                Navigator.pop(context);
                _rejectUser(context, ref, id, reasonController.text.trim());
              },
              child: const Text('Reject'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(pendingUsersProvider);

    return AppLayout(
      title: 'Approvals',
      child: RefreshIndicator(
        onRefresh: () async => ref.invalidate(pendingUsersProvider),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'User Approvals',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F)),
              ),
              const SizedBox(height: 16),
              pendingAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, stack) => Text('Error loading approvals: $err'),
                data: (users) {
                  if (users.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(32),
                      alignment: Alignment.center,
                      child: const Column(
                        children: [
                          Icon(Icons.check_circle_outline, size: 60, color: Colors.green),
                          SizedBox(height: 12),
                          Text('No pending user approval requests', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: users.length,
                    itemBuilder: (context, index) {
                      final u = users[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${u['first_name'] ?? ''} ${u['last_name'] ?? 'Pending User'}',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text('Email: ${u['email'] ?? 'N/A'}'),
                              Text('Role: ${u['role'] ?? 'student'}'),
                              Text('Requested on: ${u['created_at'] ?? 'N/A'}'),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                                      onPressed: () => _approveUser(context, ref, u['id']),
                                      child: const Text('Approve'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                      onPressed: () => _showRejectDialog(context, ref, u['id']),
                                      child: const Text('Reject'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
