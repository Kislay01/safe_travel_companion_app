// lib/main.dart
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sos_system/common/views/splash_screen.dart';
import 'package:sos_system/common/controllers/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase config is read from android/app/google-services.json (see SETUP.md).
  await Firebase.initializeApp();
  

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeController(),
      child: const AppEntry(),
    ),
  );
}

/// Use a tiny wrapper here so we can keep the provider above the MaterialApp
class AppEntry extends StatelessWidget {
  const AppEntry({super.key});

  @override
  Widget build(BuildContext context) {
    return const MyApp();
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeController = context.watch<ThemeController>();

    // While theme controller is loading saved prefs, show a minimal blank app to avoid flicker
    if (!themeController.initialized) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: SizedBox()),
      );
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TravelGuard',
      themeMode: themeController.currentTheme,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.grey[100],
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
        ),
        cardColor: Colors.white,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF121212),
          foregroundColor: Colors.white,
        ),
        cardColor: const Color(0xFF1E1E1E),
      ),

      // Start with your SplashScreen (it can navigate to ChildBottomNav when ready)
      home: const SplashScreen(),

      // If you prefer to show the bottom nav immediately, replace the previous line with:
      // home: const ChildBottomNav(),
    );
  }
}
