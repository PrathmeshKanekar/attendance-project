import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../constants/app_colors.dart';
import '../providers/auth_provider.dart';
import 'app_sidebar.dart';

class AppLayout extends StatelessWidget {
  final String        title;
  final Widget        child;
  final List<Widget>? actions;
  final Widget?       fab;

  const AppLayout({
    super.key,
    required this.title,
    required this.child,
    this.actions,
    this.fab,
  });

  static const double _breakpoint = 800;

  @override
  Widget build(BuildContext context) {
    final width     = MediaQuery.of(context).size.width;
    final isDesktop = width > _breakpoint;

    if (isDesktop) {
      return _DesktopLayout(
        title  : title,
        actions: actions,
        fab    : fab,
        child  : child,
      );
    }
    return _MobileLayout(
      title  : title,
      actions: actions,
      fab    : fab,
      child  : child,
    );
  }
}

// ── Desktop layout ─────────────────────────────────────────
class _DesktopLayout extends StatelessWidget {
  final String        title;
  final Widget        child;
  final List<Widget>? actions;
  final Widget?       fab;

  const _DesktopLayout({
    required this.title,
    required this.child,
    this.actions,
    this.fab,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: fab,
      body: Row(
        children: [
          // CRITICAL FIX: sidebar is ALWAYS rendered
          // It shows placeholder when user is loading
          const AppSidebar(),
          const VerticalDivider(
            width: 1, thickness: 1, color: AppColors.borderColor,
          ),
          Expanded(
            child: Column(
              children: [
                _TopBar(title: title, actions: actions),
                const Divider(height: 1, color: AppColors.borderColor),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Mobile layout ──────────────────────────────────────────
class _MobileLayout extends StatelessWidget {
  final String        title;
  final Widget        child;
  final List<Widget>? actions;
  final Widget?       fab;

  const _MobileLayout({
    required this.title,
    required this.child,
    this.actions,
    this.fab,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer              : const Drawer(child: AppSidebar(isDrawer: true)),
      floatingActionButton: fab,
      appBar: AppBar(
        title           : Text(title),
        actions         : actions,
        backgroundColor : AppColors.cardBg,
        elevation       : 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: child,
    );
  }
}

// ── Top bar ────────────────────────────────────────────────
class _TopBar extends ConsumerWidget {
  final String        title;
  final List<Widget>? actions;

  const _TopBar({required this.title, this.actions});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // CRITICAL FIX: use select() to prevent rebuild on loading state
    final user = ref.watch(
      authProvider.select((s) => s is AuthSuccess ? s.user : null),
    );

    return Container(
      height  : 64,
      padding : const EdgeInsets.symmetric(horizontal: 24),
      color   : AppColors.cardBg,
      child   : Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize  : 20,
                fontWeight: FontWeight.w700,
                color     : AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (actions != null) ...actions!,
          const SizedBox(width: 8),
          IconButton(
            icon     : const Icon(Icons.notifications_outlined),
            onPressed: () {
              final role = user?.role ?? 'student';
              final route = role == 'student'
                  ? '/student/notifications'
                  : '/student/notifications';
              context.push(route);
            },
            tooltip  : 'Notifications',
            color    : AppColors.textSecondary,
          ),
          const SizedBox(width: 4),
          if (user != null)
            CircleAvatar(
              radius         : 18,
              backgroundColor: AppColors.primaryLight.withOpacity(0.15),
              child          : Text(
                user.initials,
                style: const TextStyle(
                  color     : AppColors.primaryLight,
                  fontSize  : 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
