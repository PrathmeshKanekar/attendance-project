import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/constants/app_colors.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart' as custom_theme;
import 'features/virtual_rooms/virtual_rooms_screen.dart';
import 'features/virtual_rooms/add_edit_room_screen.dart';
import 'features/virtual_rooms/room_detail_screen.dart';
import 'features/virtual_rooms/room_preview_screen.dart';

class SmartCampusApp extends ConsumerWidget {
  const SmartCampusApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'Smart Campus ERP',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: custom_theme.AppTheme.light,
      darkTheme: custom_theme.AppTheme.dark,
      themeMode: ThemeMode.system,
    );
  }
}
