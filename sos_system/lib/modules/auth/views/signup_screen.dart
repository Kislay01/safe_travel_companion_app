import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sos_system/common/views/custom_appbar.dart';
import 'package:sos_system/common/views/custom_snackbar.dart';
import 'package:sos_system/modules/auth/controllers/auth_controller.dart';
import 'package:sos_system/modules/auth/models/user_model.dart';
import 'package:sos_system/modules/auth/views/login_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  String selectedRole = "Child";
  final TextEditingController nameController = TextEditingController();
  final TextEditingController mobileController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();

  bool _passwordsMismatch = false;
  bool _obscurePassword = true; // <- added
  bool _obscureConfirmPassword = true; // <- added
  bool _isLoading = false;
  late FocusNode _nameFocus;
  late FocusNode _mobileFocus;
  late FocusNode _emailFocus;
  late FocusNode _passwordFocus;
  late FocusNode _confirmPasswordFocus;

  @override
  void initState() {
    super.initState();
    _nameFocus = FocusNode();
    _mobileFocus = FocusNode();
    _emailFocus = FocusNode();
    _passwordFocus = FocusNode();
    _confirmPasswordFocus = FocusNode();

    // Rebuild when focus changes to update label color dynamically
    for (var node in [
      _nameFocus,
      _mobileFocus,
      _emailFocus,
      _passwordFocus,
      _confirmPasswordFocus,
    ]) {
      node.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    mobileController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    _nameFocus.dispose();
    _mobileFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmPasswordFocus.dispose();
    super.dispose();
  }

  InputDecoration _inputDecoration({
    required String label,
    required FocusNode focusNode,
    bool error = false,
    Widget? suffix,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = const Color(0xFF007BFF);

    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        color:
            error
                ? Colors.red
                : (focusNode.hasFocus
                    ? accent
                    : (isDark ? Colors.grey[400] : Colors.grey[700])),
      ),
      filled: true,
      fillColor: isDark ? Colors.grey[900] : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color:
              error
                  ? Colors.red
                  : (isDark ? Colors.grey[700]! : Colors.grey[400]!),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: error ? Colors.red : accent, width: 2),
      ),
      suffixIcon: suffix,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = const Color(0xFF007BFF);
    final textColor = isDark ? Colors.white : Colors.black;
    final subtitleColor = isDark ? Colors.grey[400] : Colors.black54;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const CustomAppBar(title: "Sign Up"),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Image.asset(
                "assets/images/login_page.png",
                height: 160,
                fit: BoxFit.contain,
                errorBuilder:
                    (context, error, stackTrace) =>
                        Icon(Icons.person_add, size: 120, color: accent),
              ),
              const SizedBox(height: 12),
              Text(
                "Create account",
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Sign up to get started",
                style: GoogleFonts.poppins(fontSize: 14, color: subtitleColor),
              ),
              const SizedBox(height: 20),

              // Role buttons
              Row(
                children: [
                  _buildRoleButton("Child", isDark, accent),
                  const SizedBox(width: 10),
                  _buildRoleButton("Guardian", isDark, accent),
                ],
              ),
              const SizedBox(height: 20),

              // Name field
              TextField(
                focusNode: _nameFocus,
                controller: nameController,
                textInputAction: TextInputAction.next,
                decoration: _inputDecoration(
                  label: "Name",
                  focusNode: _nameFocus,
                ),
              ),
              const SizedBox(height: 15),

              // Mobile field
              TextField(
                focusNode: _mobileFocus,
                controller: mobileController,
                textInputAction: TextInputAction.next,
                keyboardType: TextInputType.phone,
                decoration: _inputDecoration(
                  label: "Mobile Number",
                  focusNode: _mobileFocus,
                ),
              ),
              const SizedBox(height: 15),

              // Email field
              TextField(
                focusNode: _emailFocus,
                controller: emailController,
                textInputAction: TextInputAction.next,
                keyboardType: TextInputType.emailAddress,
                decoration: _inputDecoration(
                  label: "Email",
                  focusNode: _emailFocus,
                ),
              ),
              const SizedBox(height: 15),

              // Password field (with toggle)
              TextField(
                focusNode: _passwordFocus,
                controller: passwordController,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.next,
                decoration: _inputDecoration(
                  label: "Password",
                  focusNode: _passwordFocus,
                  suffix: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: isDark ? Colors.grey[400] : Colors.grey[700],
                    ),
                    onPressed:
                        () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                  ),
                ),
              ),
              const SizedBox(height: 15),

              // Confirm Password field (with toggle)
              TextField(
                focusNode: _confirmPasswordFocus,
                controller: confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                decoration: _inputDecoration(
                  label: "Confirm Password",
                  focusNode: _confirmPasswordFocus,
                  error: _passwordsMismatch,
                  suffix: IconButton(
                    icon: Icon(
                      _obscureConfirmPassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: isDark ? Colors.grey[400] : Colors.grey[700],
                    ),
                    onPressed:
                        () => setState(
                          () =>
                              _obscureConfirmPassword =
                                  !_obscureConfirmPassword,
                        ),
                  ),
                ),
              ),

              if (_passwordsMismatch) ...[
                const SizedBox(height: 8),
                Text(
                  'Password and Confirm Password do not match',
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Sign Up Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _isLoading ? null : _onSignUpPressed,
                  child: const Text(
                    "Sign Up",
                    style: TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Login Link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Already have an account?",
                    style: GoogleFonts.poppins(color: subtitleColor),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      );
                    },
                    child: Text(
                      "Log in",
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleButton(String role, bool isDark, Color accent) {
    final bool isSelected = selectedRole == role;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => selectedRole = role),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color:
                isSelected
                    ? accent
                    : (isDark ? Colors.grey[850] : Colors.grey[300]),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSelected ? accent : Colors.transparent),
          ),
          alignment: Alignment.center,
          child: Text(
            role,
            style: GoogleFonts.poppins(
              color:
                  isSelected
                      ? Colors.white
                      : (isDark ? Colors.white : Colors.black),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onSignUpPressed() async {
    if (nameController.text.trim().isEmpty ||
        mobileController.text.trim().isEmpty ||
        emailController.text.trim().isEmpty ||
        passwordController.text.trim().isEmpty ||
        confirmPasswordController.text.trim().isEmpty) {
      CustomSnackbar().showSnackBar(context, "Please fill all fields");
      return;
    }

    if (passwordController.text != confirmPasswordController.text) {
      setState(() => _passwordsMismatch = true);
      return;
    } else {
      setState(() => _passwordsMismatch = false);
    }

    //Show loading indicator
    setState(() {
      _isLoading = true;
    });

    final user = UserModel(
      uid: '',
      name: nameController.text.trim(),
      email: emailController.text.trim(),
      mobile: mobileController.text.trim(),
      role: selectedRole,
      password: passwordController.text.trim(),
    );

    final authController = AuthController();
    final error = await authController.signUp(
      user,
      passwordController.text.trim(),
    );

    if (error != null) {
      CustomSnackbar().showSnackBar(context, error);
    } else {
      if (mounted) {
        // navigate to login screen after successful signup
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    }
  }
}
