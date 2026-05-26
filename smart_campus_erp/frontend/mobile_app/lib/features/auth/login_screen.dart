import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/config/api_config.dart';
import '../../core/models/user_model.dart';
import '../../core/constants/app_constants.dart';
import '../../core/network/dio_client.dart';
import '../../core/utils/form_validators.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Email tab controllers
  final _emailCtrl    = TextEditingController();
  final _emailPwdCtrl = TextEditingController();
  final _emailFormKey = GlobalKey<FormState>();
  bool  _emailObscure = true;

  // PRN tab controllers
  final _prnCtrl    = TextEditingController();
  final _prnPwdCtrl = TextEditingController();
  final _prnFormKey = GlobalKey<FormState>();
  bool  _prnObscure = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailCtrl.dispose();
    _emailPwdCtrl.dispose();
    _prnCtrl.dispose();
    _prnPwdCtrl.dispose();
    super.dispose();
  }

  void _navigateByRole(UserModel user) {
    switch (user.role) {
      case 'student':
        context.go('/student/dashboard');
        break;
      case 'teacher':
        context.go('/teacher/dashboard');
        break;
      case 'principal':
        context.go('/principal/dashboard');
        break;
      case 'hod':
        context.go('/hod/dashboard');
        break;
      case 'college_admin':
      case 'lab_assistant':
        context.go('/admin/dashboard');
        break;
      case 'super_admin':
        context.go('/super-admin/dashboard');
        break;
      default:
        context.go('/login');
    }
  }

  void _submitEmail() {
    if (!_emailFormKey.currentState!.validate()) return;
    
    final authState = ref.read(authProvider);
    if (authState is AuthLoading) return; // Prevent duplicate

    FocusScope.of(context).unfocus();
    ref.read(authProvider.notifier).loginWithEmail(
      _emailCtrl.text.trim(),
      _emailPwdCtrl.text,
    );
  }

  void _submitPrn() {
    if (!_prnFormKey.currentState!.validate()) return;

    final authState = ref.read(authProvider);
    if (authState is AuthLoading) return; // Prevent duplicate

    FocusScope.of(context).unfocus();
    ref.read(authProvider.notifier).loginWithPrn(
      _prnCtrl.text.trim().toUpperCase(),
      _prnPwdCtrl.text,
    );
  }

  void _showBaseUrlDialog() async {
    final currentUrl = await ApiConfig.baseUrl;
    final ctrl = TextEditingController(text: currentUrl);

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Server Configuration'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter local backend server URL (include http:// and port):'),
            const SizedBox(height: 4),
            const Text(
              'Tip: Ensure your phone and PC are on the same Wi-Fi network.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                hintText: 'e.g. http://192.168.1.5:8000',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await ApiConfig.setCustomBaseUrl(ctrl.text.trim());
              if (context.mounted) Navigator.pop(context);
              messenger.showSnackBar(
                const SnackBar(content: Text('Server URL updated successfully!')),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authProvider, (prev, next) {
      if (next is AuthError) {
        final err = next.message.toLowerCase();
        if (err.contains('waiting for lab assistant approval')) {
          context.go('/pending-approval?status=pending');
        } else if (err.contains('rejected') && err.contains('registration')) {
          context.go('/pending-approval?status=rejected&message=${Uri.encodeComponent(next.message)}');
        } else if (err.contains('blocked')) {
          context.go('/pending-approval?status=blocked&message=${Uri.encodeComponent(next.message)}');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content        : Text(next.message),
              backgroundColor: AppColors.danger,
              behavior       : SnackBarBehavior.floating,
            ),
          );
        }
      }
    });

    final authState = ref.watch(authProvider);
    final isLoading = authState is AuthLoading;

    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop   = screenWidth > 800;

    return Scaffold(
      body: isDesktop
          ? _buildDesktopLayout(isLoading)
          : _buildMobileLayout(isLoading),
    );
  }

  Widget _buildDesktopLayout(bool isLoading) {
    return Row(
      children: [
        Expanded(
          flex: 6,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin : Alignment.topLeft,
                end   : Alignment.bottomRight,
                colors: [AppColors.primary, AppColors.primaryLight],
              ),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width : 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color       : Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Icon(
                      Icons.school_rounded,
                      size : 60,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'SMART CAMPUS',
                    style: TextStyle(
                      color      : Colors.white,
                      fontSize   : 36,
                      fontWeight : FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Attendance ERP System',
                    style: TextStyle(
                      color   : Colors.white.withOpacity(0.80),
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 48),
                  _buildFeatureItem(Icons.location_on, 'Geo-Fencing Validation'),
                  const SizedBox(height: 16),
                  _buildFeatureItem(Icons.face, 'Face Recognition'),
                  const SizedBox(height: 16),
                  _buildFeatureItem(Icons.remove_red_eye, 'Liveness Detection'),
                  const SizedBox(height: 16),
                  _buildFeatureItem(Icons.school, 'Multi-College SaaS'),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          flex: 4,
          child: Container(
            color : AppColors.cardBg,
            child : Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(48),
                child : ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child      : _buildLoginCard(isLoading),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureItem(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            color   : Colors.white.withOpacity(0.90),
            fontSize: 16,
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(bool isLoading) {
    return Stack(
      children: [
        Container(
          height: MediaQuery.of(context).size.height * 0.35,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin : Alignment.topLeft,
              end   : Alignment.bottomRight,
              colors: [AppColors.primary, AppColors.primaryLight],
            ),
          ),
        ),

        SafeArea(
          child: Column(
            children: [
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.28,
                child : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.school_rounded,
                      size : 52,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'SMART CAMPUS',
                      style: TextStyle(
                        color     : Colors.white,
                        fontSize  : 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Attendance ERP',
                      style: TextStyle(
                        color   : Colors.white.withOpacity(0.80),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color       : AppColors.cardBg,
                    borderRadius: BorderRadius.only(
                      topLeft : Radius.circular(28),
                      topRight: Radius.circular(28),
                    ),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child  : _buildLoginCard(isLoading),
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: SafeArea(
            child: IconButton(
              icon: const Icon(Icons.settings, color: Colors.white),
              onPressed: _showBaseUrlDialog,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginCard(bool isLoading) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Welcome Back',
          style: TextStyle(
            fontSize  : 26,
            fontWeight: FontWeight.bold,
            color     : AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Sign in to your account',
          style: TextStyle(
            fontSize: 14,
            color   : AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 28),

        Container(
          decoration: BoxDecoration(
            color       : AppColors.bgSecondary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: TabBar(
            controller      : _tabController,
            indicator       : BoxDecoration(
              color        : AppColors.primaryLight,
              borderRadius : BorderRadius.circular(10),
            ),
            indicatorSize   : TabBarIndicatorSize.tab,
            labelColor      : Colors.white,
            unselectedLabelColor: AppColors.textSecondary,
            labelStyle      : const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize  : 14,
            ),
            unselectedLabelStyle: const TextStyle(fontSize: 14),
            dividerColor    : Colors.transparent,
            tabs: const [
              Tab(text: 'Email'),
              Tab(text: 'PRN Number'),
            ],
          ),
        ),

        const SizedBox(height: 24),

        SizedBox(
          height: 280,
          child : TabBarView(
            controller: _tabController,
            children  : [
              _buildEmailTab(isLoading),
              _buildPrnTab(isLoading),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmailTab(bool isLoading) {
    return Form(
      key: _emailFormKey,
      child: Column(
        children: [
          TextFormField(
            controller  : _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration  : const InputDecoration(
              hintText    : 'Email address',
              prefixIcon  : Icon(Icons.email_outlined),
            ),
            validator: FormValidators.email,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller  : _emailPwdCtrl,
            obscureText : _emailObscure,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submitEmail(),
            decoration  : InputDecoration(
              hintText   : 'Password',
              prefixIcon : const Icon(Icons.lock_outline),
              suffixIcon : IconButton(
                icon     : Icon(
                  _emailObscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: () =>
                    setState(() => _emailObscure = !_emailObscure),
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Password is required';
              if (v.length < 6) return 'Minimum 6 characters';
              return null;
            },
          ),
          const SizedBox(height: 20),
          isLoading
              ? const SizedBox(
                  height: 52,
                  child : Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.primaryLight,
                      ),
                    ),
                  ),
                )
              : ElevatedButton(
                  onPressed: _submitEmail,
                  child    : const Text('Login'),
                ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("New Student? "),
              TextButton(
                onPressed: () => context.go('/register'),
                child: const Text('Register Now'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPrnTab(bool isLoading) {
    return Form(
      key: _prnFormKey,
      child: Column(
        children: [
          TextFormField(
            controller     : _prnCtrl,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.next,
            decoration     : const InputDecoration(
              hintText   : 'PRN Number (e.g. DEC2024001)',
              prefixIcon : Icon(Icons.badge_outlined),
            ),
            validator: (v) => FormValidators.required(v, 'PRN number'),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller  : _prnPwdCtrl,
            obscureText : _prnObscure,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submitPrn(),
            decoration  : InputDecoration(
              hintText   : 'Password',
              prefixIcon : const Icon(Icons.lock_outline),
              suffixIcon : IconButton(
                icon     : Icon(
                  _prnObscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: () =>
                    setState(() => _prnObscure = !_prnObscure),
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Password is required';
              if (v.length < 6) return 'Minimum 6 characters';
              return null;
            },
          ),
          const SizedBox(height: 20),
          isLoading
              ? const SizedBox(
                  height: 52,
                  child : Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.primaryLight,
                      ),
                    ),
                  ),
                )
              : ElevatedButton(
                  onPressed: _submitPrn,
                  child    : const Text('Login with PRN'),
                ),
        ],
      ),
    );
  }
}
