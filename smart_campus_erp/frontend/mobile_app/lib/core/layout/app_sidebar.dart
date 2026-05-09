import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../constants/app_colors.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import 'nav_config.dart';
import 'nav_item.dart';
import 'sidebar_state.dart';

class AppSidebar extends ConsumerWidget {
  final bool isDrawer;
  const AppSidebar({super.key, this.isDrawer = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // CRITICAL FIX: use select() — only rebuild when user changes
    // NOT on every auth state transition (loading etc.)
    final user = ref.watch(
      authProvider.select((s) => s is AuthSuccess ? s.user : null),
    );

    final isExpanded = ref.watch(sidebarProvider);

    // CRITICAL FIX: never hide sidebar — show placeholder while loading
    if (user == null) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width   : isDrawer ? 260 : (isExpanded ? 260 : 68),
        color   : AppColors.sidebarBg,
        child   : const Center(
          child: SizedBox(
            width : 20, height: 20,
            child : CircularProgressIndicator(
              strokeWidth: 2,
              valueColor : AlwaysStoppedAnimation(Colors.white30),
            ),
          ),
        ),
      );
    }

    final items = NavConfig.getItems(user.role);
    final width = isDrawer ? 260.0
        : (isExpanded ? 260.0 : 68.0);

    return AnimatedContainer(
      duration : const Duration(milliseconds: 250),
      curve    : Curves.easeInOut,
      width    : width,
      color    : AppColors.sidebarBg,
      child    : Column(
        children: [
          _buildLogoSection(context, ref, user, isExpanded, isDrawer),
          const Divider(color: Colors.white12, height: 1),
          Expanded(
            child: ListView.builder(
              padding    : const EdgeInsets.symmetric(vertical: 8),
              itemCount  : items.length,
              itemBuilder: (context, index) => _NavItemTile(
                item      : items[index],
                isExpanded: isExpanded || isDrawer,
              ),
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          _buildUserCard(context, ref, user, isExpanded || isDrawer),
        ],
      ),
    );
  }

  Widget _buildLogoSection(BuildContext context, WidgetRef ref,
      UserModel user, bool isExpanded, bool isDrawer) {
    return SizedBox(
      height: 70,
      child : Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child  : Row(
          children: [
            Container(
              width : 38, height: 38,
              decoration: BoxDecoration(
                color       : Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.school_rounded, color: Colors.white, size: 22,
              ),
            ),
            if (isExpanded || isDrawer) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment : MainAxisAlignment.center,
                  children: [
                    const Text(
                      'SMART CAMPUS',
                      style: TextStyle(
                        color: Colors.white, fontSize: 13,
                        fontWeight: FontWeight.w800, letterSpacing: 0.8,
                      ),
                    ),
                    if (user.collegeName != null)
                      Text(
                        user.collegeName!,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.55),
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
            const Spacer(),
            if (!isDrawer)
              IconButton(
                icon     : Icon(
                  isExpanded
                      ? Icons.chevron_left_rounded
                      : Icons.chevron_right_rounded,
                  color: Colors.white54, size: 22,
                ),
                onPressed: () =>
                    ref.read(sidebarProvider.notifier).toggle(),
                padding  : EdgeInsets.zero,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserCard(BuildContext context, WidgetRef ref,
      UserModel user, bool isExpanded) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child  : Row(
        children: [
          CircleAvatar(
            radius         : 18,
            backgroundColor: Colors.white.withOpacity(0.20),
            child          : Text(
              user.initials,
              style: const TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (isExpanded) ...[
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.fullName,
                    style: const TextStyle(
                      color: Colors.white, fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color       : NavConfig.roleColor(user.role)
                          .withOpacity(0.30),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      NavConfig.roleLabel(user.role),
                      style: TextStyle(
                        color    : NavConfig.roleColor(user.role),
                        fontSize : 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon     : const Icon(
                Icons.logout_rounded, color: Colors.white54, size: 20,
              ),
              onPressed: () async {
                await ref.read(authProvider.notifier).logout();
                if (context.mounted) context.go('/login');
              },
              tooltip  : 'Logout',
              padding  : EdgeInsets.zero,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Nav item tile with freeze fix ─────────────────────────
class _NavItemTile extends ConsumerStatefulWidget {
  final NavItem item;
  final bool    isExpanded;
  const _NavItemTile({required this.item, required this.isExpanded});

  @override
  ConsumerState<_NavItemTile> createState() => _NavItemTileState();
}

class _NavItemTileState extends ConsumerState<_NavItemTile> {
  // CRITICAL FIX: debounce to prevent multiple rapid taps
  bool _navigating = false;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final isActive = location == widget.item.route
        || location.startsWith('${widget.item.route}/');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child  : AnimatedContainer(
        duration   : const Duration(milliseconds: 200),
        decoration : BoxDecoration(
          gradient   : isActive
              ? const LinearGradient(
                  colors: [Color(0xFF2563EB), Color(0xFF0EA5E9)],
                )
              : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap       : () {
              // CRITICAL FIX 1: already on this route — do nothing
              if (isActive) return;

              // CRITICAL FIX 2: debounce rapid taps
              if (_navigating) return;
              _navigating = true;
              Future.delayed(
                const Duration(milliseconds: 500),
                () { if (mounted) _navigating = false; },
              );

              // CRITICAL FIX 3: close drawer if open on mobile
              if (Scaffold.of(context).isDrawerOpen) {
                Navigator.of(context).pop();
              }

              // CRITICAL FIX 4: use go() for clean stack
              context.go(widget.item.route);
            },
            hoverColor  : Colors.white.withOpacity(0.08),
            splashColor : Colors.white.withOpacity(0.12),
            child       : Padding(
              padding: EdgeInsets.symmetric(
                horizontal: widget.isExpanded ? 12 : 0,
                vertical  : 11,
              ),
              child: Row(
                mainAxisAlignment: widget.isExpanded
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  Icon(
                    widget.item.icon,
                    size : 22,
                    color: isActive
                        ? Colors.white
                        : Colors.white.withOpacity(0.55),
                  ),
                  if (widget.isExpanded) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.item.label,
                        style: TextStyle(
                          color     : isActive
                              ? Colors.white
                              : Colors.white.withOpacity(0.70),
                          fontSize  : 14,
                          fontWeight: isActive
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
