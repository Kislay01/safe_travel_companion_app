import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";
import "package:sos_system/common/views/custom_appbar.dart";

class AboutUs extends StatelessWidget {
  const AboutUs({super.key});

  static const _team = ['Kislay Upadhyay', 'Vishwajit Suryawanshi'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: "About Us"),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: ClipOval(
                child: Image.asset(
                  "assets/images/travelguard_logo.png",
                  width: 120,
                  height: 120,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'TravelGuard',
              style: GoogleFonts.manrope(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              "TravelGuard keeps travellers safe and gives their guardians peace of mind. "
              "It shares live location with trusted guardians, alerts them when a journey "
              "starts and when you arrive, and sends an instant SOS with your location in "
              "an emergency — by pressing a button or just by saying \"help me\".",
              style: GoogleFonts.manrope(fontSize: 14),
            ),
            const SizedBox(height: 20),
            Text(
              'What TravelGuard does',
              style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            _feature(context, Icons.my_location, "Live location sharing with your guardians"),
            _feature(context, Icons.route, "Journeys with turn-by-turn voice directions"),
            _feature(context, Icons.notifications_active_outlined,
                "Guardian alerts when a journey starts, ends or is completed"),
            _feature(context, Icons.sos, "SOS by button or voice, with your location"),
            _feature(context, Icons.health_and_safety_outlined,
                "\"Are you OK?\" check-ins from your guardian"),
            _feature(context, Icons.chat_outlined, "Chat and one-tap calling"),
            const SizedBox(height: 20),
            Text(
              'Developed by',
              style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            for (final name in _team) _buildNavTile(Icons.person, name, context),
          ],
        ),
      ),
    );
  }

  Widget _feature(BuildContext context, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF0F766E), size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: GoogleFonts.manrope(fontSize: 14))),
        ],
      ),
    );
  }

  Widget _buildNavTile(IconData icon, String title, BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 60,
      margin: const EdgeInsets.only(bottom: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: isDarkMode ? const Color(0xFF172220) : Colors.white,
      ),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF0F766E)),
        title: Text(title, style: GoogleFonts.manrope(fontSize: 15)),
      ),
    );
  }
}
