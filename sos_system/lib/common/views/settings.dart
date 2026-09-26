// lib/modules/yourpath/settings.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sos_system/common/views/aboutus.dart';
import 'package:sos_system/common/views/location_sharing_info_page.dart';
import 'package:sos_system/common/views/trusted_guardian.dart';
import 'package:sos_system/modules/auth/views/login_screen.dart';
import 'package:sos_system/common/views/custom_appbar.dart';
import 'package:provider/provider.dart';
import 'package:sos_system/common/controllers/theme_controller.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  bool _isNotificationOn = true;
  bool _isSosOn = true;

  // Firestore / auth for primary contact feature
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  List<Map<String, dynamic>> _contacts = [];
  String? _selectedContactDocId;
  bool _loadingContacts = false;
  String _childEmail = '';

  @override
  void initState() {
    super.initState();
    _initChildEmailAndContacts();
  }

  Future<void> _initChildEmailAndContacts() async {
    setState(() => _loadingContacts = true);
    try {
      final sp = await SharedPreferences.getInstance();
      final storedEmail = sp.getString('email') ?? '';
      final current = _auth.currentUser?.email ?? '';
      _childEmail = storedEmail.isNotEmpty ? storedEmail : current;

      if (_childEmail.trim().isEmpty) {
        _contacts = [];
        _selectedContactDocId = null;
        setState(() => _loadingContacts = false);
        return;
      }

      final snapshot = await _firestore
          .collection('Child')
          .doc(_childEmail)
          .collection('emergency_contacts')
          .orderBy('isPrimary', descending: true)
          .get();

      _contacts = snapshot.docs.map((d) {
        final data = d.data();
        return {
          'docId': d.id,
          'name': (data['name'] ?? '').toString(),
          'email': (data['email'] ?? '').toString(),
          'mobile': (data['mobile'] ?? '').toString(),
          'isPrimary': data['isPrimary'] == true,
        };
      }).toList();

      final primaryIndex = _contacts.indexWhere((c) => c['isPrimary'] == true);
      if (primaryIndex >= 0) {
        _selectedContactDocId = _contacts[primaryIndex]['docId'] as String;
      } else if (_contacts.isNotEmpty) {
        _selectedContactDocId = _contacts.first['docId'] as String;
      } else {
        _selectedContactDocId = null;
      }
    } catch (e) {
      debugPrint('Error loading contacts: $e');
      _contacts = [];
      _selectedContactDocId = null;
    } finally {
      setState(() => _loadingContacts = false);
    }
  }

  Future<void> _setPrimaryContact(String? docId) async {
    if (docId == null || _childEmail.trim().isEmpty) return;
    setState(() => _loadingContacts = true);

    try {
      final colRef = _firestore.collection('Child').doc(_childEmail).collection('emergency_contacts');
      final snapshot = await colRef.get();

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        final isSelected = doc.id == docId;
        batch.update(doc.reference, {'isPrimary': isSelected});
      }
      await batch.commit();

      for (var c in _contacts) {
        c['isPrimary'] = (c['docId'] == docId);
      }
      setState(() => _selectedContactDocId = docId);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primary contact updated')),
      );
    } catch (e) {
      debugPrint('Error setting primary contact: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update primary contact: $e')),
      );
    } finally {
      setState(() => _loadingContacts = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeController = Provider.of<ThemeController>(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: const CustomAppBar(title: "Settings"),
      // Scrollable body with safe intrinsic height to avoid bottom overflow
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(20.0),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Appearance", style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),

                    _buildSwitchTile(
                      icon: Icons.dark_mode_outlined,
                      title: "Dark Mode",
                      value: themeController.isDark,
                      onChanged: (value) => themeController.toggleTheme(value),
                      context: context,
                    ),

                    const SizedBox(height: 20),
                    Text("Notifications", style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),

                    _buildSwitchTile(
                      icon: Icons.notifications_none,
                      title: "Push Notifications",
                      value: _isNotificationOn,
                      onChanged: (value) => setState(() => _isNotificationOn = value),
                      context: context,
                    ),

                    const SizedBox(height: 5),

                    _buildSwitchTile(
                      icon: Icons.security,
                      title: "SOS Alerts",
                      value: _isSosOn,
                      onChanged: (value) => setState(() => _isSosOn = value),
                      context: context,
                    ),


                    // Primary Contact chooser
                    const SizedBox(height: 20),
                    Text("Primary Contact", style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    Container(
                      height: 70,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
                      ),
                      child: _loadingContacts
                          ? Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                                  SizedBox(width: 12),
                                  Text('Loading contacts...'),
                                ],
                              ),
                            )
                          : (_contacts.isEmpty)
                              ? Center(child: Text('No emergency contacts available', style: GoogleFonts.poppins()))
                              : Row(
                                  children: [
                                    Icon(Icons.contact_page_outlined, color: const Color.fromRGBO(0, 123, 255, 1.0)),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String>(
                                          isExpanded: true,
                                          value: _selectedContactDocId,
                                          hint: Text('Select primary contact', style: GoogleFonts.poppins()),
                                          items: _contacts.map((c) {
                                            final label = (c['name'] != null && (c['name'] as String).isNotEmpty)
                                                ? c['name']
                                                : (c['mobile'] ?? 'Unnamed');
                                            return DropdownMenuItem<String>(
                                              value: c['docId'] as String,
                                              child: Text(label.toString(), style: GoogleFonts.poppins()),
                                            );
                                          }).toList(),
                                          onChanged: (newVal) async {
                                            if (newVal != null && newVal != _selectedContactDocId) {
                                              await _setPrimaryContact(newVal);
                                            }
                                          },
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (_selectedContactDocId != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.shade100,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          'Primary',
                                          style: GoogleFonts.poppins(fontSize: 12, color: Colors.black),
                                        ),
                                      ),
                                  ],
                                ),
                    ),

                    const SizedBox(height: 20),
                    Text("Privacy & Security", style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),

                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const LocationSharingInfoPage()),
                        );
                      },
                      child: _buildNavTile(Icons.location_on_outlined, "Location Sharing", context),
                    ),

                    

                    // const SizedBox(height: 12),

                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const TrustedGuardian()),
                        );
                      },
                      child: _buildNavTile(Icons.shield_outlined, "Trusted Guardians", context),
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const AboutUs()),
                        );
                      },
                      child: _buildNavTile(Icons.info_outline_rounded, "About Us", context),
                    ),

                    // Spacer ensures content pushes up and bottomNavigationBar is visible
                    const Spacer(),
                    // Small hint text above bottom bar (optional)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Center(
                        child: Text('You can change the primary emergency contact above.', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),

      // Logout button placed in bottomNavigationBar to avoid overflow
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: SizedBox(
          height: 45,
          child: ElevatedButton(
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              SharedPreferences sharedPreferencesObj = await SharedPreferences.getInstance();
              await sharedPreferencesObj.clear();

              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) {
                  return LoginScreen();
                }),
                (route) => false,
              );
            },
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              minimumSize: const Size(double.infinity, 56),
              backgroundColor: Colors.red[100],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.logout, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Text(
                  "Logout",
                  style: GoogleFonts.poppins(
                    color: Colors.red,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),

      backgroundColor: isDarkMode ? const Color(0xFF121212) : Colors.grey[100],
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required bool value,
    required Function(bool) onChanged,
    required BuildContext context,
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
      ),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          children: [
            Icon(icon, color: const Color.fromRGBO(0, 123, 255, 1.0)),
            const SizedBox(width: 10),
            Text(title, style: GoogleFonts.poppins(fontSize: 15)),
            const Spacer(),
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: Colors.white,
              inactiveThumbColor: Colors.white,
              activeTrackColor: Colors.green,
              inactiveTrackColor: Colors.grey[400],
            ),
          ],
        ),
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
        color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
      ),
      child: ListTile(
        leading: Icon(icon, color: const Color.fromRGBO(0, 123, 255, 1.0)),
        title: Text(title, style: GoogleFonts.poppins(fontSize: 15)),
        trailing: Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey[600], size: 18),
      ),
    );
  }
}
