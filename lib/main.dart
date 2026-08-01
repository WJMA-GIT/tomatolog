import 'package:flutter/material.dart';

import 'controllers/app_controller.dart';
import 'screens/home_shell.dart';
import 'screens/timer_screen.dart';
import 'services/app_platform_service.dart';
import 'services/app_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final platform = AppPlatformService();
  final controller = AppController(SharedPreferencesAppStorage(), platform);
  final navigatorKey = GlobalKey<NavigatorState>();
  await controller.load();
  await platform.listenForNotificationActions(() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final context = navigatorKey.currentContext;
      if (context != null) await showTimerEndDialog(context, controller);
    });
  });
  runApp(TimeTomatoApp(controller: controller, navigatorKey: navigatorKey));
}

class TimeTomatoApp extends StatefulWidget {
  const TimeTomatoApp({super.key, required this.controller, this.navigatorKey});

  final AppController controller;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<TimeTomatoApp> createState() => _TimeTomatoAppState();
}

class _TimeTomatoAppState extends State<TimeTomatoApp> {
  late AppThemePreference _preference = widget.controller.themePreference;
  late int _accentColorValue = widget.controller.accentColorValue;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleSettingsChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleSettingsChange);
    super.dispose();
  }

  void _handleSettingsChange() {
    final preference = widget.controller.themePreference;
    final accentColorValue = widget.controller.accentColorValue;
    if (preference != _preference || accentColorValue != _accentColorValue) {
      setState(() {
        _preference = preference;
        _accentColorValue = accentColorValue;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: widget.navigatorKey,
      debugShowCheckedModeBanner: false,
      title: '番茄日志',
      themeMode: switch (_preference) {
        AppThemePreference.system => ThemeMode.system,
        AppThemePreference.light => ThemeMode.light,
        AppThemePreference.dark => ThemeMode.dark,
      },
      theme: _theme(Brightness.light, Color(_accentColorValue)),
      darkTheme: _theme(Brightness.dark, Color(_accentColorValue)),
      home: HomeShell(controller: widget.controller),
    );
  }
}

ThemeData _theme(Brightness brightness, Color accentColor) {
  final isDark = brightness == Brightness.dark;
  final surface = isDark ? Colors.black : const Color(0xFFF7F7F7);
  final scheme = ColorScheme.fromSeed(
    seedColor: accentColor,
    brightness: brightness,
  ).copyWith(surface: surface);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: surface,
    canvasColor: surface,
    dialogTheme: DialogThemeData(backgroundColor: surface),
    cardTheme: const CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(backgroundColor: surface),
  );
}
