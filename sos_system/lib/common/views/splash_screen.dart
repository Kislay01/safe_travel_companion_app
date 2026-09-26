import 'dart:developer';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:sos_system/modules/auth/controllers/shared_preference_data.dart';
import 'package:sos_system/modules/auth/views/login_screen.dart';
import 'package:sos_system/modules/child/views/child_bottom_nav.dart';
import 'package:sos_system/modules/guardian/views/guardian_bottom_nav.dart';
import 'package:sos_system/services/location_sharing_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _rotationController;
  late AnimationController _popController;
  late AnimationController _bgController;
  late Animation<double> _popAnimation;
  late Animation<Color?> _bgColor1;
  late Animation<Color?> _bgColor2;

  @override
  void initState() {
    super.initState();

    // 🌀 Logo rotation controller (3s)
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    // 💥 Text pop-up controller (starts after rotation)
    _popController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // 🌈 Background gradient fade-in controller
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    // 🎬 Pop animation with bounce
    _popAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.2)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.2, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 40,
      ),
    ]).animate(_popController);

    // 🌈 Animate between dark colors for cinematic effect
    _bgColor1 = ColorTween(
      begin: Colors.black,
      end: const Color(0xFF001F3F), // deep navy blue
    ).animate(CurvedAnimation(parent: _bgController, curve: Curves.easeInOut));

    _bgColor2 = ColorTween(
      begin: Colors.black,
      end: const Color(0xFF003366), // dark blue tone
    ).animate(CurvedAnimation(parent: _bgController, curve: Curves.easeInOut));

    // Start both animations in sequence
    _bgController.forward();
    _rotationController.forward();
    _rotationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _popController.forward();
      }
    });

    navigateToScreen();
  }

  Future<void> navigateToScreen() async {
    // Keep splash visible until all animations finish
    await Future.delayed(const Duration(seconds: 4));

    SharedPreferenceData sharedPreferenceObj = SharedPreferenceData();
    await sharedPreferenceObj.getSharedPreferenceData();
    // log("Is User Logged In: ${sharedPreferenceObj.isUserLoggedIn}");
    // log("Role: ${sharedPreferenceObj.role}");
    // log("Email: ${sharedPreferenceObj.email}");

    if (sharedPreferenceObj.isUserLoggedIn &&
        sharedPreferenceObj.role == "Child") {
      final locationService =
          LocationSharingService(childEmail: sharedPreferenceObj.email);
      locationService.startSharing();

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const ChildBottomNav(),
        ),
      );
    } else if (sharedPreferenceObj.isUserLoggedIn &&
        sharedPreferenceObj.role == "Guardian") {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => GuardianBottomNav(
            guardianEmail: sharedPreferenceObj.email,
          ),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const LoginScreen(),
        ),
      );
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _popController.dispose();
    _bgController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_bgColor1, _bgColor2]),
      builder: (context, child) {
        return Scaffold(
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_bgColor1.value!, _bgColor2.value!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 🌀 3D Rotating logo
                  AnimatedBuilder(
                    animation: _rotationController,
                    builder: (context, child) {
                      final rotationValue =
                          _rotationController.value * 2 * pi;
                      return Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.002)
                          ..rotateY(rotationValue),
                        child: ClipOval(
                          child: Image.asset(
                            "assets/images/MyGuardian.png",
                            height: 300,
                            width: 300,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),

                  // 💥 Pop-up animated app name
                  ScaleTransition(
                    scale: _popAnimation,
                    child: const Text(
                      "MyGuardian",
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
