// lib/modules/Guardian/views/guardian_emergency_contact_list.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sos_system/common/views/add_emergency_contacts.dart';
import 'package:sos_system/common/views/custom_appbar.dart';
import 'package:sos_system/modules/auth/controllers/shared_preference_data.dart';
import 'package:url_launcher/url_launcher.dart'; // ✅ Added for phone call

class GuardianEmergencyContactList extends StatefulWidget {
  const GuardianEmergencyContactList({super.key});

  @override
  State<GuardianEmergencyContactList> createState() => _GuardianEmergencyContactListState();
}

class _GuardianEmergencyContactListState extends State<GuardianEmergencyContactList> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SharedPreferenceData _prefs = SharedPreferenceData();
  String guardianEmail = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initPrefs();
  }

  Future<void> _initPrefs() async {
    await _prefs.getSharedPreferenceData();
    final fallbackEmail = FirebaseAuth.instance.currentUser?.email ?? '';
    setState(() {
      guardianEmail = (_prefs.email != null && _prefs.email.isNotEmpty) ? _prefs.email : fallbackEmail;
      _loading = false;
    });
  }

  Future<bool> _confirmAndDelete(DocumentReference contactRef, {required String contactName, required bool isPrimary}) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Delete contact', style: GoogleFonts.poppins()),
          content: Text(
            isPrimary
                ? '“$contactName” is marked as Primary. Are you sure you want to delete this contact?'
                : 'Are you sure you want to delete “$contactName”?',
            style: GoogleFonts.poppins(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel', style: GoogleFonts.poppins()),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('Delete', style: GoogleFonts.poppins(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (confirm != true) return false;

    try {
      await contactRef.delete();
      if (!mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted contact: $contactName')),
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete contact: $e')),
      );
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenWidth = mq.size.width;
    final screenHeight = mq.size.height;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    double avatarSize = (screenWidth * 0.16).clamp(48.0, 80.0);
    double containerHeight = (avatarSize + 26).clamp(84.0, 120.0);
    double horizontalPadding = (screenWidth * 0.04).clamp(12.0, 24.0);
    double verticalPadding = (screenHeight * 0.015).clamp(8.0, 18.0);
    double nameFontSize = (screenWidth < 360) ? 16.0 : 18.0;
    double relationshipFontSize = (screenWidth < 360) ? 13.0 : 14.0;
    double primaryTagFont = (screenWidth < 360) ? 11.0 : 12.0;

    final backgroundColor = isDark ? const Color(0xFF121212) : Colors.grey[100];
    final cardColor = Theme.of(context).cardColor;
    final textColor = isDark ? Colors.white : Colors.black;
    final subTextColor = isDark ? Colors.grey[400] : Colors.grey[700];

    if (_loading) {
      return Scaffold(
        appBar: const CustomAppBar(title: "Emergency Contacts"),
        backgroundColor: backgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (guardianEmail.trim().isEmpty) {
      return Scaffold(
        appBar: const CustomAppBar(title: "Emergency Contacts"),
        backgroundColor: backgroundColor,
        body: Center(
          child: Text(
            "No guardian user found. Please sign in or set the guardian profile.",
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(color: subTextColor),
          ),
        ),
        floatingActionButton: Padding(
          padding: EdgeInsets.only(bottom: (screenHeight * 0.01).clamp(8.0, 20.0)),
          child: SizedBox(
            height: (screenWidth * 0.16).clamp(48.0, 72.0),
            width: (screenWidth * 0.16).clamp(48.0, 72.0),
            child: FloatingActionButton(
              backgroundColor: const Color.fromRGBO(0, 123, 255, 1.0),
              foregroundColor: Colors.white,
              shape: const CircleBorder(),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (c) => const AddEmergencyContacts()),
                );
                await _initPrefs();
              },
              child: Icon(
                Icons.add,
                size: (screenWidth * 0.07).clamp(20.0, 32.0),
              ),
            ),
          ),
        ),
      );
    }

    final Stream<QuerySnapshot> contactStream = _firestore
        .collection('Guardian')
        .doc(guardianEmail)
        .collection('emergency_contacts')
        .orderBy('isPrimary', descending: true)
        .snapshots();

    return Scaffold(
      appBar: const CustomAppBar(title: "Emergency Contacts"),
      backgroundColor: backgroundColor,
      body: StreamBuilder<QuerySnapshot>(
        stream: contactStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Text(
                "No emergency contacts found.",
                style: TextStyle(color: subTextColor),
              ),
            );
          }

          final docs = snapshot.data!.docs;

          return ListView.builder(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final name = (data['name'] ?? '').toString();
              final relationship = (data['relationship'] ?? '').toString();
              final phone = (data['mobile'] ?? '').toString();
              final isPrimary = data['isPrimary'] == true;

              // Visible contact card
              final contactCard = Padding(
                padding: EdgeInsets.symmetric(vertical: verticalPadding / 2),
                child: Container(
                  height: containerHeight,
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding * 0.3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: cardColor,
                    boxShadow: [
                      if (!isDark)
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.08),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Avatar
                      Container(
                        height: avatarSize,
                        width: avatarSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                            width: 1,
                          ),
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            "assets/images/profile.jpg",
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.person,
                              size: avatarSize * 0.6,
                              color: isDark ? Colors.grey[300] : Colors.grey[700],
                            ),
                          ),
                        ),
                      ),

                      SizedBox(width: horizontalPadding * 0.6),

                      // Details
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final isNarrow = constraints.maxWidth < 220 || screenWidth < 360;
                            return Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        name,
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                        style: GoogleFonts.poppins(
                                          fontSize: nameFontSize,
                                          fontWeight: FontWeight.w600,
                                          color: textColor,
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: isNarrow ? 6 : 12),
                                    if (isPrimary)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.shade100,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          'Primary',
                                          style: GoogleFonts.poppins(
                                            fontSize: primaryTagFont,
                                            color: Colors.black,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: [
                                    ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxWidth: isNarrow ? constraints.maxWidth : constraints.maxWidth * 0.6,
                                      ),
                                      child: Text(
                                        relationship,
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                        style: GoogleFonts.poppins(
                                          fontSize: relationshipFontSize,
                                          color: subTextColor,
                                        ),
                                      ),
                                    ),
                                    if (phone.isNotEmpty)
                                      Text(
                                        "• $phone",
                                        style: GoogleFonts.poppins(
                                          fontSize: relationshipFontSize,
                                          color: subTextColor,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      ),

                      const SizedBox(width: 10),

                      // Call Button
                      GestureDetector(
                        onTap: () async {
                          final phoneNumber = phone.trim();
                          if (phoneNumber.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Phone number not available')),
                            );
                            return;
                          }

                          final Uri telUri = Uri(scheme: 'tel', path: phoneNumber);

                          try {
                            if (await canLaunchUrl(telUri)) {
                              await launchUrl(telUri, mode: LaunchMode.externalApplication);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Could not open dialer')),
                              );
                            }
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error opening dialer: $e')),
                            );
                          }
                        },
                        child: Container(
                          height: (avatarSize * 0.65).clamp(40.0, 56.0),
                          width: (avatarSize * 0.65).clamp(40.0, 56.0),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color.fromRGBO(0, 123, 255, 1.0),
                          ),
                          child: const Icon(Icons.call_outlined, color: Colors.white),
                        ),
                      ),

                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              );

              // Delete background shown while swiping left (endToStart)
              final deleteBackground = Container(
                margin: EdgeInsets.symmetric(vertical: verticalPadding / 2),
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding * 0.4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.red.shade600,
                ),
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Delete', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 12),
                    Icon(Icons.delete, color: Colors.white),
                  ],
                ),
              );

              return Dismissible(
                key: ValueKey(doc.id),
                direction: DismissDirection.endToStart, // swipe left to reveal delete
                confirmDismiss: (direction) async {
                  final success = await _confirmAndDelete(doc.reference, contactName: name, isPrimary: isPrimary);
                  return success;
                },
                background: deleteBackground,
                child: contactCard,
              );
            },
          );
        },
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: (screenHeight * 0.01).clamp(8.0, 20.0)),
        child: SizedBox(
          height: (screenWidth * 0.16).clamp(48.0, 72.0),
          width: (screenWidth * 0.16).clamp(48.0, 72.0),
          child: FloatingActionButton(
            backgroundColor: const Color.fromRGBO(0, 123, 255, 1.0),
            foregroundColor: Colors.white,
            shape: const CircleBorder(),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (c) => const AddEmergencyContacts()),
              );
            },
            child: Icon(
              Icons.add,
              size: (screenWidth * 0.07).clamp(20.0, 32.0),
            ),
          ),
        ),
      ),
    );
  }
}
