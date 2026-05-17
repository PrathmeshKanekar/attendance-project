import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // ── GLOBAL ERROR HANDLING ──────────────────────────────────────
  FlutterError.onError = (details) {
    print('Flutter Error: ${details.exception}');
    print('Stack trace: ${details.stack}');
  };

  await Hive.initFlutter();
  
  runApp(
    const ProviderScope(
      child: SmartCampusApp(),
    ),
  );
}
