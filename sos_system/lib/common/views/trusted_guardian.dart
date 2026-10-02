import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";
import "package:sos_system/common/views/custom_appbar.dart";

class TrustedGuardian extends StatelessWidget {
  const TrustedGuardian({super.key});

  @override
  Widget build(BuildContext context) {
    // final themeController = Provider.of<ThemeController>(context);
    // final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: const CustomAppBar(title: "Trusted Guardian"),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'What is Trusted Guardian?',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "A Trusted Guardian is someone you rely on for safety and support. In TravelGuard, they are the people who will be notified instantly if you are in an emergency or need help.",
              style: GoogleFonts.poppins(fontSize: 16, height: 1.4),
            ),
            const SizedBox(height: 20),
            Text(
              'Purpose',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "The Trusted Guardian feature ensures you're never alone during unexpected situations. Whether you're travelling, walking alone, or facing danger — your guardians will always know your location and can reach you quickly.",
              style: GoogleFonts.poppins(fontSize: 16, height: 1.4),
            ),
            const SizedBox(height: 20),

            Text(
              'How It Works',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text('''
1. Add Guardians: Choose trusted friends or family members to be your guardians within the app.
2. Instant Alerts: In an emergency, simply press the SOS button to send an instant alert to your guardians.
3. Real-Time Location: Your guardians receive your live location, allowing them to assist you or notify authorities if needed.
4. Safety Check-Ins: You can also send regular check-ins to your guardians to let them know you're safe.
              ''', style: GoogleFonts.poppins(fontSize: 16, height: 1.4)),

            Text(
              'Privacy & Control',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "TravelGuard shares your location only with your verified guardians. All your information remains secure, encrypted, and under your control. You can edit or remove guardians anytime from your profile settings.",
              style: GoogleFonts.poppins(fontSize: 16, height: 1.4),
            ),

            SizedBox(height: 30,),

            Text(
              'Stay Safe. Stay Connected. Always with TravelGuard.',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),

            SizedBox(height: 20,)
              
          ],
        ),
      ),
    );
  }

  //  Add this method inside the class
  Widget _mentorCard(String imagePath, String name) {
    return Column(
      children: [
        ClipOval(
          child: Image.asset(
            imagePath,
            width: 100,
            height: 100,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          name,
          style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildNavTile(IconData icon, String title, BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 60,
      margin: const EdgeInsets.only(bottom: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
      ),
      child: ListTile(
        leading: Icon(icon, color: const Color.fromRGBO(0, 123, 255, 1.0)),
        title: Text(title, style: GoogleFonts.poppins(fontSize: 15)),
        // trailing: Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey[600], size: 18),
      ),
    );
  }
}
