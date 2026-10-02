// lib/modules/auth/views/login_screen.dart
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sos_system/common/views/custom_appbar.dart';
import 'package:sos_system/common/views/custom_snackbar.dart';
import 'package:sos_system/modules/auth/controllers/auth_controller.dart';
import 'package:sos_system/modules/auth/views/forgot_password.dart';
import 'package:sos_system/modules/auth/views/signup_screen.dart';
import 'package:sos_system/modules/child/views/child_bottom_nav.dart';
import 'package:sos_system/modules/guardian/views/guardian_bottom_nav.dart';
import 'package:sos_system/services/session_services.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String selectedRole = "Child";
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool _loginFailed = false;
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;
    final titleColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.grey[400] : Colors.black54;
    final borderColor =
        _loginFailed ? Colors.red : (isDark ? Colors.grey[700]! : Colors.grey);
    final accent = const Color.fromRGBO(0, 123, 255, 1.0);

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: const CustomAppBar(title: "Secure Login"),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Login image
              SizedBox(
                height: 180,
                child: Image.asset(
                  "assets/images/login_page.png",
                  fit: BoxFit.contain,
                  errorBuilder: (ctx, err, st) =>
                      Icon(Icons.lock, size: 120, color: accent),
                ),
              ),
              const SizedBox(height: 12),

              // Welcome Text
              Text('Welcome back',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: titleColor)),
              const SizedBox(height: 6),
              Text('Sign in to continue to your account',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(fontSize: 14, color: subtitleColor)),
              const SizedBox(height: 16),

              // Role selector
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildRoleButton("Child", isDark, accent),
                  const SizedBox(width: 10),
                  _buildRoleButton("Guardian", isDark, accent),
                ],
              ),
              const SizedBox(height: 18),

              // Email field
              TextField(
                controller: usernameController,
                textInputAction: TextInputAction.next,
                onChanged: (_) {
                  if (_loginFailed) setState(() => _loginFailed = false);
                },
                style:
                    TextStyle(color: isDark ? Colors.white : Colors.black87),
                decoration: InputDecoration(
                  hintText: "Email",
                  hintStyle:
                      TextStyle(color: isDark ? Colors.grey[400] : Colors.grey),
                  filled: true,
                  fillColor: isDark ? Colors.grey[900] : Colors.white,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        BorderSide(color: _loginFailed ? Colors.red : accent),
                  ),
                ),
              ),
              const SizedBox(height: 15),

              // Password field
              TextField(
                controller: passwordController,
                obscureText: _obscurePassword,
                onChanged: (_) {
                  if (_loginFailed) setState(() => _loginFailed = false);
                },
                style:
                    TextStyle(color: isDark ? Colors.white : Colors.black87),
                decoration: InputDecoration(
                  hintText: "Password",
                  hintStyle:
                      TextStyle(color: isDark ? Colors.grey[400] : Colors.grey),
                  filled: true,
                  fillColor: isDark ? Colors.grey[900] : Colors.white,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        BorderSide(color: _loginFailed ? Colors.red : accent),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: isDark ? Colors.grey[400] : Colors.grey[700],
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),

              if (_loginFailed) ...[
                const SizedBox(height: 8),
                Text(
                  'Invalid username, password, or role',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.red, fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 8),

              // Forgot Password
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ForgotPasswordScreen()));
                  },
                  child: Text("Forgot Password?",
                      style: TextStyle(
                          color: accent, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 10),

              // Login button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isLoading ? Colors.grey : accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _isLoading ? null : _handleLogin,
                  child: _isLoading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text("Login",
                          style:
                              TextStyle(fontSize: 16, color: Colors.white)),
                ),
              ),
              const SizedBox(height: 10),

              // Signup link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text("Don't have an account?",
                      style: GoogleFonts.poppins(color: subtitleColor)),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SignUpScreen()));
                    },
                    child: Text("Sign Up",
                        style: TextStyle(
                            color: accent, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Handles login logic
  Future<void> _handleLogin() async {
    final email = usernameController.text.trim().toLowerCase();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() => _loginFailed = true);
      CustomSnackbar().showSnackBar(context, "Please enter email and password");
      return;
    }

    setState(() => _isLoading = true);
    final authController = AuthController();

    final error = await authController.login(email, password, selectedRole);
    if (error != null) {
      setState(() {
        _loginFailed = true;
        _isLoading = false;
      });
      CustomSnackbar().showSnackBar(context, error);
      return;
    }

    try {
      final doc =
          await authController.firestore.collection(selectedRole).doc(email).get();
      final userData = doc.data() ?? {};

      // Save user details
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isUserLoggedIn', true);
      await prefs.setString('uid', authController.firebaseAuth.currentUser!.uid);
      await prefs.setString('role', selectedRole);
      await prefs.setString('name', userData['name'] ?? '');
      await prefs.setString('email', userData['email'] ?? '');
      await prefs.setString('mobile', userData['mobile'] ?? '');

      log("User Details Saved in SharedPreferences: $userData");

      SessionServices.start(
        role: selectedRole,
        email: (userData['email'] ?? email).toString(),
        name: (userData['name'] ?? '').toString(),
      );
      if (!mounted) return;

      // Navigate
      if (selectedRole == "Child") {
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const ChildBottomNav()));
      } else {
        final guardianEmail = userData['email'] ?? email;
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => GuardianBottomNav(guardianEmail: guardianEmail)));
      }
    } catch (e) {
      setState(() {
        _loginFailed = true;
      });
      CustomSnackbar().showSnackBar(context, "Failed to retrieve user data");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Builds the role selection button
  Widget _buildRoleButton(String role, bool isDark, Color accent) {
    final bool isSelected = selectedRole == role;
    final unselectedBg = isDark ? Colors.grey[850] : Colors.grey[300];
    final unselectedText = isDark ? Colors.white : Colors.black87;

    return SizedBox(
      width: 140,
      child: GestureDetector(
        onTap: () {
          setState(() {
            selectedRole = role;
            _loginFailed = false;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? accent : unselectedBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: isSelected ? accent : Colors.transparent, width: 1),
          ),
          alignment: Alignment.center,
          child: Text(
            role,
            style: GoogleFonts.poppins(
                color: isSelected ? Colors.white : unselectedText,
                fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
