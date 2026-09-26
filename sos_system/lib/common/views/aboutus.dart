import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";
import "package:sos_system/common/views/custom_appbar.dart";

class AboutUs extends StatelessWidget{

  const AboutUs({super.key});

  @override
  Widget build(BuildContext context) {
    // final themeController = Provider.of<ThemeController>(context);
    // final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: const CustomAppBar(title: "About Us",),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'MyGuardian',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "MyGuardian app is designed to keep children safe and give guardians peace of mind.It tracks live location of children sends instant SOS alerts in emergencies,and allows guardians to monitor their child's safety easily.With user-friendly features and reliable performance,my guardian app is the ultimate safety companion for families.receives instant SOS alerts with location details, enabling quick response in emergencies.",
              style: GoogleFonts.poppins(fontSize: 16, height: 1.4),
            ),
            const SizedBox(height: 20),
            Text(
              'About MyGuardian',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "MyGuardian app is smart safety solution built to protect children and informed at all times Accurate location tracking Quick SoS alerts for emergencies journey history and reports Instant notificattions and updates",
              style: GoogleFonts.poppins(fontSize: 16, height: 1.4),
            ),
            const SizedBox(height: 20),
            Text(
              'Mentors',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _mentorCard("assets/images/shashi_sir.png", 'Shashi Sir'),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              "We extend our heartfelt gratitude to our guide Shashi Sir and Akshay Sir and mentors Prajwal Dada, Rahul Dada, and Sayli Di for their constant guidance, motivation, and encouragement. Their invaluable support, constructive feedback, and real-world insights have helped shape our learning experience and inspired us to build PrepLink as a platform that helps others in the same way they helped us.",
              style: GoogleFonts.poppins(fontSize: 16, height: 1.4),
            ),
            const SizedBox(height: 20),
            Text(
              'Our Team',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10,),

            _buildNavTile(Icons.person, "Pawan Ingole", context),
            _buildNavTile(Icons.person, "Shruti Siddha", context),
            _buildNavTile(Icons.person, "Satyam Patil", context),
            _buildNavTile(Icons.person, "Pranav Siddha", context),
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



