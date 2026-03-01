import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme/app_theme.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/connectivity_service.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'screens/usage_permission_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait mode
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppTheme.surface,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Initialize Firebase
  await Firebase.initializeApp();

  // Initialize notifications
  await NotificationService.initialize();

  // Get saved session
  final prefs = await SharedPreferences.getInstance();
  final savedUid = prefs.getString('session_uid');
  final savedGroupId = prefs.getString('session_group_id');

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AuthService()
            ..initSession(savedUid, savedGroupId),
        ),
        ChangeNotifierProvider(
          create: (_) => ConnectivityService(),
        ),
      ],
      child: const YapapaApp(),
    ),
  );
}

class YapapaApp extends StatelessWidget {
  const YapapaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Yapapa',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const AppRouter(),
    );
  }
}

class AppRouter extends StatefulWidget {
  const AppRouter({super.key});

  @override
  State<AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends State<AppRouter> {
  bool _showUsagePermission = false;
  bool _checkingPermission = true;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final show = await shouldShowUsagePermission();
    if (mounted) {
      setState(() {
        _showUsagePermission = show;
        _checkingPermission = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    if (auth.isLoading || _checkingPermission) {
      return const SplashScreen();
    }

    // Show usage permission screen once on first login
    if (auth.currentUser != null && _showUsagePermission) {
      return UsagePermissionScreen(
        onDone: () => setState(() => _showUsagePermission = false),
      );
    }

    if (auth.currentUser == null) {
      return const LoginScreen();
    }

    return const MainShell();
  }
}
