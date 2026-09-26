// lib/modules/guardian/views/guardian_chat_list.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sos_system/common/views/chat_page.dart';
import 'package:sos_system/common/views/custom_appbar.dart';
import 'package:sos_system/modules/auth/controllers/shared_preference_data.dart';

class GuardianChatList extends StatefulWidget {
  const GuardianChatList({super.key});

  @override
  State<GuardianChatList> createState() => _GuardianChatListState();
}

class _GuardianChatListState extends State<GuardianChatList> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SharedPreferenceData _prefs = SharedPreferenceData();

  String userEmail = '';
  String userRole = 'Guardian';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    await _prefs.getSharedPreferenceData();
    setState(() {
      userEmail = _prefs.email;
      userRole = _prefs.role.isNotEmpty ? _prefs.role : 'Guardian';
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardColor;
    final textColor = isDark ? Colors.white : Colors.black;
    final subTextColor = isDark ? Colors.grey[400] : Colors.grey[700];

    if (_loading) {
      return Scaffold(
        appBar: const CustomAppBar(title: "Chat"),
        backgroundColor: isDark ? const Color(0xFF121212) : Colors.grey[100],
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (userEmail.isEmpty) {
      return Scaffold(
        appBar: const CustomAppBar(title: "Chat"),
        backgroundColor: isDark ? const Color(0xFF121212) : Colors.grey[100],
        body: Center(child: Text("No contacts found, Please add emergency contact", style: TextStyle(color: textColor))),
      );
    }

    // Path depends on role — for Guardian we read Guardian/{email}/emergency_contacts
    final collectionPath = userRole == 'Guardian'
        ? _firestore.collection('Guardian').doc(userEmail).collection('emergency_contacts')
        : _firestore.collection('Child').doc(userEmail).collection('emergency_contacts');

    final stream = collectionPath.orderBy('isPrimary', descending: true).snapshots();

    return Scaffold(
      appBar: const CustomAppBar(title: "Chat"),
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.grey[100],
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: StreamBuilder<QuerySnapshot>(
          stream: stream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return Center(child: Text("No contacts found.", style: TextStyle(color: subTextColor)));
            }

            final docs = snapshot.data!.docs;

            return ListView.separated(
              itemCount: docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final doc = docs[index];
                final data = doc.data() as Map<String, dynamic>;
                final name = data['name'] ?? '';
                final relationship = data['relationship'] ?? '';
                final mobile = data['mobile'] ?? '';
                final email = data['email'] ?? '';
                final isPrimary = (data['isPrimary'] ?? false) as bool;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChatScreen(
                            name: name,
                            relationship: relationship,
                            myEmail: userEmail,
                            otherEmail: email,
                            isChildSide: userRole == 'Child',
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(12),
                    splashColor: isDark ? Colors.blueGrey[800] : Colors.blue.withOpacity(0.08),
                    child: Container(
                      height: 90,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: cardColor,
                        boxShadow: [
                          if (!isDark)
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.08),
                              blurRadius: 3,
                              offset: const Offset(0, 1),
                            ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            Container(
                              height: 60,
                              width: 60,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                                  width: 1,
                                ),
                              ),
                              child: ClipOval(
                                child: Image.asset("assets/images/profile.jpg", fit: BoxFit.cover),
                              ),
                            ),
                            const SizedBox(width: 15),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(name, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: textColor)),
                                      const SizedBox(width: 8),
                                      if (isPrimary)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.amber.shade100,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text('Primary', style: GoogleFonts.poppins(fontSize: 12, color: Colors.black)),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(relationship, style: GoogleFonts.poppins(fontSize: 14, color: subTextColor)),
                                ],
                              ),
                            ),
                            Container(
                              height: 38,
                              width: 38,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isDark ? Colors.blueGrey[800] : Colors.blue[50],
                              ),
                              child: const Icon(Icons.message_outlined, color: Color.fromRGBO(0, 123, 255, 1.0), size: 20),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
