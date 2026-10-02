import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final Widget? leading;

  const CustomAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AppBar(
      title: Text(
        title,
        style: GoogleFonts.poppins(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : Colors.black,
        ),
      ),
      centerTitle: true,
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      elevation: 0,
      leading: leading ?? Padding(
        padding: const EdgeInsets.all(8.0),
        child: _LogoCircle(isDark: isDark),
      ),
      actions: actions,
      iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _LogoCircle extends StatelessWidget {
  final bool isDark;
  const _LogoCircle({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final asset = 'assets/images/travelguard_logo.png';

    // Choose background so logo is visible on dark AppBar
    final bg = isDark ? Colors.white12 : Colors.transparent;

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: Image.asset(
          asset,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stack) {
            // fallback icon shown on load error
            // ignore: avoid_print
            print('Logo asset load failed: $error');
            return Icon(Icons.shield, size: 28, color: isDark ? Colors.white : Colors.black);
          },
        ),
      ),
    );
  }
}
