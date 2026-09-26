import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";
import "package:sos_system/common/views/custom_appbar.dart";

class LocationSharingInfoPage extends StatelessWidget {
  const LocationSharingInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    // final themeController = Provider.of<ThemeController>(context);
    // final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: const CustomAppBar(title: "Location Sharing Info"),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Introduction',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Location sharing is a key feature of MyGuardian, designed to help your trusted guardians know where you are when it matters most. It ensures that in emergencies, your loved ones can quickly find and reach you without delay.",
              style: GoogleFonts.poppins(fontSize: 16, height: 1.4),
            ),
            const SizedBox(height: 20),
            Text(
              'What Location Sharing Does',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "When you enable location sharing, MyGuardian continuously updates your real-time location to your selected trusted guardians. In case of an emergency, they receive your exact location instantly, allowing them to assist you or notify authorities if needed.",
              style: GoogleFonts.poppins(fontSize: 16, height: 1.4),
            ),
            const SizedBox(height: 20),

            Text(
              'When to Use Location Sharing',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text('''
1. Emergencies: Instantly share your location with guardians during an SOS alert.
2. Traveling Alone: Keep guardians informed of your whereabouts when going out alone.
3. Unsafe Situations: Share your location if you feel unsafe or threatened.
4. Check-Ins: Let your guardians know you're safe by sharing your location periodically.

              ''', style: GoogleFonts.poppins(fontSize: 16, height: 1.4)),

            SizedBox(height: 25,),

            Text(
              'Your location saves time - and time saves lives.',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              // textAlign: TextAlign.center,
            ),

            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '-Team MyGuardian',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.end,
                ),
              ],
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
