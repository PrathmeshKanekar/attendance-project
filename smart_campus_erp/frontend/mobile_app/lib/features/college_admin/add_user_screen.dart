import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/layout/app_layout.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/loading_widget.dart';
import 'providers/academic_providers.dart';

class AddUserScreen extends ConsumerStatefulWidget {
  const AddUserScreen({super.key});

  @override
  ConsumerState<AddUserScreen> createState() => _AddUserScreenState();
}

class _AddUserScreenState extends ConsumerState<AddUserScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _errorMessage;

  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  String _role = 'student';
  bool _obscurePassword = true;

  // Student specific
  final _prnCtrl = TextEditingController();
  final _rollNumberCtrl = TextEditingController();
  int _yearOfStudy = 1;
  String? _selectedDivisionId;

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _prnCtrl.dispose();
    _rollNumberCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final Map<String, dynamic> data = {
        'first_name': _firstNameCtrl.text.trim(),
        'last_name': _lastNameCtrl.text.trim(),
        'email': _emailCtrl.text.trim().toLowerCase(),
        'phone': _phoneCtrl.text.trim(),
        'password': _passwordCtrl.text,
        'role': _role,
      };

      if (_role == 'student') {
        data['prn'] = _prnCtrl.text.trim().toUpperCase();
        data['roll_number'] = _rollNumberCtrl.text.trim();
        data['year_of_study'] = _yearOfStudy;
        data['division_id'] = _selectedDivisionId;
      }

      await ref.read(apiClientProvider).post('/api/auth/users/create/', data: data);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User created successfully. Awaiting approval.'),
            backgroundColor: AppColors.success,
          ),
        );
        context.pop();
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final divisionsAsync = ref.watch(divisionsProvider);
    final principalExistsAsync = ref.watch(principalExistsProvider);
    
    final rolesNeedingPrincipal = ['teacher', 'hod', 'lab_assistant'];
    final selectedRoleNeedsPrincipal = rolesNeedingPrincipal.contains(_role);
    
    final hasPrincipal = principalExistsAsync.value ?? false;
    final isCreationBlocked = selectedRoleNeedsPrincipal && !hasPrincipal;

    return AppLayout(
      title: 'Add New User',
      child: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.danger),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: AppColors.danger, fontSize: 13),
                      ),
                    ),

                  // ── Section 1: Basic Info ────────────────────────
                  const _SectionHeader(title: 'Basic Information'),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _firstNameCtrl,
                          decoration: const InputDecoration(labelText: 'First Name *'),
                          validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _lastNameCtrl,
                          decoration: const InputDecoration(labelText: 'Last Name *'),
                          validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email Address *', prefixIcon: Icon(Icons.email_outlined)),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      if (!v.contains('@')) return 'Invalid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone Number (Optional)', prefixIcon: Icon(Icons.phone_outlined)),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordCtrl,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Password *',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: (v) => (v == null || v.length < 8) ? 'At least 8 characters' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirmPasswordCtrl,
                    obscureText: _obscurePassword,
                    decoration: const InputDecoration(labelText: 'Confirm Password *', prefixIcon: Icon(Icons.lock_outline_rounded)),
                    validator: (v) {
                      if (v != _passwordCtrl.text) return 'Passwords do not match';
                      return null;
                    },
                  ),

                  // ── Section 2: Role ──────────────────────────────
                  const SizedBox(height: 32),
                  const _SectionHeader(title: 'Account Role'),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _role,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.badge_outlined)),
                    items: const [
                      DropdownMenuItem(value: 'student', child: Text('Student')),
                      DropdownMenuItem(value: 'teacher', child: Text('Teacher')),
                      DropdownMenuItem(value: 'hod', child: Text('HOD')),
                      DropdownMenuItem(value: 'principal', child: Text('Principal')),
                      DropdownMenuItem(value: 'lab_assistant', child: Text('Lab Assistant')),
                    ],
                    onChanged: (v) => setState(() => _role = v!),
                  ),

                  if (selectedRoleNeedsPrincipal) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: hasPrincipal 
                            ? AppColors.success.withOpacity(0.08)
                            : Colors.orange.withOpacity(0.08),
                        border: Border(
                          left: BorderSide(
                            color: hasPrincipal ? AppColors.success : Colors.orange, 
                            width: 4,
                          ),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            hasPrincipal ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                            color: hasPrincipal ? AppColors.success : Colors.orange,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              hasPrincipal 
                                  ? 'Principal verified. You can proceed with staff creation.'
                                  : 'A Principal must be approved before you can add Teachers or Staff.',
                              style: TextStyle(
                                color: hasPrincipal ? AppColors.success : Colors.orange, 
                                fontSize: 13, 
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          if (!hasPrincipal)
                            IconButton(
                              icon: const Icon(Icons.refresh, size: 20, color: Colors.orange),
                              onPressed: () => ref.invalidate(principalExistsProvider),
                            ),
                        ],
                      ),
                    ),
                  ],

                  // ── Section 3: Student Details ───────────────────
                  if (_role == 'student') ...[
                    const SizedBox(height: 32),
                    const _SectionHeader(title: 'Student Details'),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _prnCtrl,
                      decoration: const InputDecoration(labelText: 'PRN Number *', hintText: 'e.g. 12345678A'),
                      validator: (v) => (_role == 'student' && (v == null || v.isEmpty)) ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _rollNumberCtrl,
                      decoration: const InputDecoration(labelText: 'Roll Number *'),
                      validator: (v) => (_role == 'student' && (v == null || v.isEmpty)) ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      value: _yearOfStudy,
                      decoration: const InputDecoration(labelText: 'Year of Study'),
                      items: [1, 2, 3, 4].map((y) => DropdownMenuItem(value: y, child: Text('Year $y'))).toList(),
                      onChanged: (v) => setState(() => _yearOfStudy = v!),
                    ),
                    const SizedBox(height: 16),
                    divisionsAsync.when(
                      data: (list) => DropdownButtonFormField<String>(
                        value: _selectedDivisionId,
                        decoration: const InputDecoration(labelText: 'Division *'),
                        items: list
                            .map((d) => DropdownMenuItem(value: d['id'] as String, child: Text('${d['name']} (${d['course_name']})')))
                            .toList(),
                        onChanged: (v) => setState(() => _selectedDivisionId = v),
                        validator: (v) => (_role == 'student' && v == null) ? 'Required' : null,
                      ),
                      loading: () => const LinearProgressIndicator(),
                      error: (e, _) => Text('Error loading divisions: $e', style: const TextStyle(color: AppColors.danger)),
                    ),
                  ],

                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: (_isLoading || isCreationBlocked) ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isCreationBlocked ? Colors.grey : AppColors.primary,
                      ),
                      child: _isLoading 
                          ? const CircularProgressIndicator(color: Colors.white) 
                          : Text(isCreationBlocked ? 'Principal Required' : 'Create User'),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
          if (_isLoading) const LoadingWidget(message: 'Creating user account...'),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: AppColors.primaryLight,
        letterSpacing: 1.2,
      ),
    );
  }
}
