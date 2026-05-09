import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/models/user_model.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeCtrl;
  late Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync   : this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(
      parent: _fadeCtrl, curve: Curves.easeIn,
    );
    _fadeCtrl.forward();

    // CRITICAL FIX: auth restore runs in AuthNotifier constructor
    // We just need to listen for result here
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _listenAndNavigate();
    });
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _listenAndNavigate() async {
    // Wait minimum 1.5s for branding visibility
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;

    final authState = ref.read(authProvider);

    if (authState is AuthSuccess) {
      _navigate(authState.user);
      return;
    }

    if (authState is AuthUnauthenticated || authState is AuthError) {
      if (mounted) context.go('/login');
      return;
    }

    // Still loading — wait for it to complete
    if (authState is AuthInitial || authState is AuthLoading) {
      ref.listen<AuthState>(authProvider, (_, next) {
        if (!mounted) return;
        if (next is AuthSuccess) {
          _navigate(next.user);
        } else if (next is AuthUnauthenticated || next is AuthError) {
          context.go('/login');
        }
      });
    }
  }

  void _navigate(UserModel user) {
    if (!mounted) return;
    switch (user.role) {
      case 'student':       context.go('/student/dashboard');      break;
      case 'teacher':       context.go('/teacher/dashboard');      break;
      case 'principal':     context.go('/principal/dashboard');    break;
      case 'hod':           context.go('/hod/dashboard');          break;
      case 'college_admin': context.go('/admin/dashboard');        break;
      case 'lab_assistant': context.go('/admin/dashboard');        break;
      case 'super_admin':   context.go('/super-admin/dashboard');  break;
      default:              context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin  : Alignment.topLeft,
            end    : Alignment.bottomRight,
            colors : [AppColors.primary, AppColors.primaryLight],
          ),
        ),
        child: FadeTransition(
          opacity: _fadeAnim,
          child  : Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width      : 100, height: 100,
                  decoration : BoxDecoration(
                    color       : Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.school_rounded,
                    size : 60, color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'SMART CAMPUS',
                  style: TextStyle(
                    color      : Colors.white,
                    fontSize   : 28,
                    fontWeight : FontWeight.w800,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Attendance ERP System',
                  style: TextStyle(
                    color  : Colors.white.withOpacity(0.80),
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 60),
                SizedBox(
                  width: 160,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child       : LinearProgressIndicator(
                      backgroundColor: Colors.white.withOpacity(0.20),
                      valueColor     : const AlwaysStoppedAnimation<Color>(
                        Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
