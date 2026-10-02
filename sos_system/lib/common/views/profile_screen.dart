// lib/modules/auth/views/profile_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart' hide Settings;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sos_system/common/views/custom_appbar.dart';
import 'package:sos_system/common/views/custom_snackbar.dart';
import 'package:sos_system/common/views/settings.dart';
import 'package:sos_system/modules/auth/controllers/shared_preference_data.dart';
import 'package:flutter/services.dart';
import 'package:sos_system/services/invite_service.dart';
import 'package:url_launcher/url_launcher.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // Display variables
  String name = "";
  String role = "";
  String phone = "";
  String email = "";

  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  String _inviteCode = '';

  // Firestore / Auth / Prefs
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SharedPreferenceData _prefs = SharedPreferenceData();

  @override
  void initState() {
    super.initState();
    _loadFromPrefsThenProfile().then((_) => _loadInviteCode());
  }

  Future<void> _loadInviteCode() async {
    if (email.isEmpty || role.isEmpty) return;
    try {
      final code = await InviteService.ensureCode(email: email, role: role, name: name);
      if (mounted) setState(() => _inviteCode = code);
    } catch (e) {
      debugPrint('Invite code: $e');
    }
  }

  String get _inviteMessage {
    final other = role == 'Child' ? 'Guardian' : 'Child';
    return 'Join me on TravelGuard so we can keep each other safe! '
        'Install the app, sign up as a $other and enter my invite code $_inviteCode.';
  }

  Future<void> _shareInvite() async {
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(_inviteMessage)}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      await Clipboard.setData(ClipboardData(text: _inviteMessage));
      if (mounted) CustomSnackbar().showSnackBar(context, "Invite message copied");
    }
  }

  Widget _buildInviteCard(Color? cardColor, Color textColor, Color subTextColor) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Invite ${role == 'Child' ? 'a guardian' : 'your child'}",
                style: GoogleFonts.poppins(fontSize: 13, color: subTextColor)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _inviteCode.isEmpty ? "Generating…" : _inviteCode,
                    style: GoogleFonts.poppins(
                        fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 2, color: textColor),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy code',
                  icon: const Icon(Icons.copy),
                  onPressed: _inviteCode.isEmpty
                      ? null
                      : () async {
                          await Clipboard.setData(ClipboardData(text: _inviteCode));
                          if (mounted) CustomSnackbar().showSnackBar(context, "Invite code copied");
                        },
                ),
                IconButton(
                  tooltip: 'Share on WhatsApp',
                  icon: const Icon(Icons.share),
                  onPressed: _inviteCode.isEmpty ? null : _shareInvite,
                ),
              ],
            ),
            Text("They enter this code when signing up and you are linked automatically.",
                style: GoogleFonts.poppins(fontSize: 12, color: subTextColor)),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  // First try to load stored prefs, then load profile from Firestore
  Future<void> _loadFromPrefsThenProfile() async {
    setState(() => _isLoading = true);
    try {
      await _prefs.getSharedPreferenceData();
      final storedEmail = _prefs.email;
      final storedRole = _prefs.role;

      if (storedEmail.isNotEmpty && storedRole.isNotEmpty) {
        // Prefs available — fetch only from that collection
        final doc = await _firestore.collection(storedRole).doc(storedEmail).get();
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          setState(() {
            name = (data['name'] ?? '') as String;
            email = (data['email'] ?? storedEmail) as String;
            phone = (data['mobile'] ?? '') as String;
            role = (data['role'] ?? storedRole) as String;
            _isLoading = false;
          });
          return;
        } else {
          // Prefs present but doc missing — fallback to lookup behavior
          CustomSnackbar().showSnackBar(context, "Profile not found in ${storedRole}. Attempting fallback.");
        }
      }

      // Fallback: check both top-level collections
      await _loadProfileFallback();
    } catch (e) {
      CustomSnackbar().showSnackBar(context, "Failed to load profile: $e");
      setState(() => _isLoading = false);
    }
  }

  // Fallback search in both collections (used when prefs empty or doc not present)
  Future<void> _loadProfileFallback() async {
    try {
      final User? currentUser = _auth.currentUser;
      final userEmail = currentUser?.email ?? _prefs.email;

      if (userEmail == null || userEmail.isEmpty) {
        CustomSnackbar().showSnackBar(context, "User email not available.");
        setState(() => _isLoading = false);
        return;
      }

      final rolesToCheck = ['Child', 'Guardian'];
      DocumentSnapshot<Map<String, dynamic>>? foundDoc;
      String foundRole = "";

      for (final r in rolesToCheck) {
        final doc = await _firestore.collection(r).doc(userEmail).get();
        if (doc.exists) {
          foundDoc = doc as DocumentSnapshot<Map<String, dynamic>>;
          foundRole = r;
          break;
        }
      }

      if (foundDoc == null) {
        // Not found — use Firebase Auth info as last resort
        setState(() {
          name = currentUser?.displayName ?? "";
          email = userEmail;
          phone = currentUser?.phoneNumber ?? "";
          role = "";
          _isLoading = false;
        });
        CustomSnackbar().showSnackBar(context, "Profile not found in Firestore. Showing basic info.");
        return;
      }

      final data = foundDoc.data()!;
      // Save found role/email into SharedPreferences for next time
      await _prefs.setSharedPreferenceData({
        'name': data['name'] ?? '',
        'email': data['email'] ?? userEmail,
        'role': data['role'] ?? foundRole,
        'uid': data['uid'] ?? currentUser?.uid ?? '',
        'mobile': data['mobile'] ?? '',
        'loginFlag': true,
      });

      setState(() {
        name = (data['name'] ?? '') as String;
        email = (data['email'] ?? userEmail) as String;
        phone = (data['mobile'] ?? '') as String;
        role = (data['role'] ?? foundRole) as String;
        _isLoading = false;
      });
    } catch (e) {
      CustomSnackbar().showSnackBar(context, "Failed to load profile: $e");
      setState(() => _isLoading = false);
    }
  }

  void _openEditSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardColor;
    final textColor = isDark ? Colors.white : Colors.black;
    final hintColor = isDark ? Colors.grey[400] : Colors.grey[600];

    // prefill controllers
    _nameCtrl.text = name;
    _phoneCtrl.text = phone;
    _emailCtrl.text = email;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[700] : Colors.grey[300],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    "Edit Profile",
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _nameCtrl,
                    label: "Name",
                    textColor: textColor,
                    hintColor: hintColor!,
                    cardColor: cardColor,
                  ),
                  const SizedBox(height: 10),
                  _buildTextField(
                    controller: _phoneCtrl,
                    label: "Phone Number",
                    keyboard: TextInputType.phone,
                    textColor: textColor,
                    hintColor: hintColor,
                    cardColor: cardColor,
                  ),

                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color.fromRGBO(0, 123, 255, 1.0),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: _isSaving ? null : () async {
                            Navigator.of(context).pop(); // close sheet
                            await _saveProfileEdits();
                          },
                          child: _isSaving
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(
                                  "Save",
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
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
      },
    );
  }

  Future<void> _saveProfileEdits() async {
    final newName = _nameCtrl.text.trim();
    final newPhone = _phoneCtrl.text.trim();
    // Email is the account ID (also the Firebase login), so it can't be changed here.
    final newEmail = email;

    if (newName.isEmpty || newPhone.isEmpty || newEmail.isEmpty) {
      CustomSnackbar().showSnackBar(context, "Please fill all fields.");
      return;
    }

    setState(() => _isSaving = true);

    try {
      final User? currentUser = _auth.currentUser;
      final originalEmail = email;
      String saveCollection = role.isNotEmpty ? role : _prefs.role;

      // If prefs and role both empty, default to checking both and choose first found
      if (saveCollection.isEmpty) {
        // determine collection by checking originalEmail doc presence
        final docChild = await _firestore.collection('Child').doc(originalEmail).get();
        if (docChild.exists) {
          saveCollection = 'Child';
        } else {
          final docGuard = await _firestore.collection('Guardian').doc(originalEmail).get();
          saveCollection = docGuard.exists ? 'Guardian' : 'Child';
        }
      }

      // Prepare updated data, preserving uid if exists
      final Map<String, dynamic> updatedData = {
        'name': newName,
        'mobile': newPhone,
        'email': newEmail,
        'role': saveCollection,
      };

      // Preserve uid if present in existing doc
      final existingDoc = await _firestore.collection(saveCollection).doc(originalEmail).get();
      if (existingDoc.exists && existingDoc.data() != null && existingDoc.data()!['uid'] != null) {
        updatedData['uid'] = existingDoc.data()!['uid'];
      } else {
        updatedData['uid'] = currentUser?.uid ?? '';
      }

      // Write updated doc under newEmail
      await _firestore.collection(saveCollection).doc(newEmail).set(updatedData);

      // If email changed and old doc existed, delete old doc
      if (newEmail != originalEmail) {
        final oldDocRef = _firestore.collection(saveCollection).doc(originalEmail);
        final oldDoc = await oldDocRef.get();
        if (oldDoc.exists) {
          await oldDocRef.delete();
        }
      }

      // Update SharedPreferences with new info
      await _prefs.setSharedPreferenceData({
        'name': newName,
        'email': newEmail,
        'role': saveCollection,
        'uid': updatedData['uid'] ?? '',
        'mobile': newPhone,
        'loginFlag': true,
      });

      setState(() {
        name = newName;
        phone = newPhone;
        email = newEmail;
        role = saveCollection;
        _isSaving = false;
      });

      CustomSnackbar().showSnackBar(context, "Profile updated successfully.");
    } catch (e) {
      setState(() => _isSaving = false);
      CustomSnackbar().showSnackBar(context, "Failed to update profile: $e");
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required Color textColor,
    required Color hintColor,
    required Color cardColor,
    TextInputType keyboard = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      style: GoogleFonts.poppins(color: textColor),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.poppins(color: hintColor),
        filled: true,
        fillColor: cardColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardColor;
    final textColor = isDark ? Colors.white : Colors.black;
    final subTextColor = isDark ? Colors.grey[400] : Colors.grey[600];
    final backgroundColor = isDark ? const Color(0xFF121212) : Colors.grey[50];

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: CustomAppBar(
        title: "Profile",
        actions: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const Settings()),
                );
              },
              child: const Icon(
                Icons.settings_outlined,
                color: Color.fromRGBO(0, 123, 255, 1.0),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Column(
                children: [
                  const SizedBox(height: 6),
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundImage: const AssetImage("assets/images/profile.jpg"),
                        backgroundColor: Colors.transparent,
                      ),
                      GestureDetector(
                        onTap: _openEditSheet,
                        child: Container(
                          height: 30,
                          width: 30,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.blueGrey[700] : Colors.blue[100],
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.edit_outlined,
                            color: Color.fromRGBO(0, 123, 255, 1.0),
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    name.isNotEmpty ? name : "User",
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  Text(
                    role.isNotEmpty ? role : "No Role",
                    style: GoogleFonts.poppins(fontSize: 14, color: subTextColor),
                  ),
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Personal Information",
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                    color: cardColor,
                    child: Column(
                      children: [
                        _infoTile(label: "Name", value: name, textColor: textColor, subTextColor: subTextColor!),
                        const Divider(height: 1),
                        _infoTile(label: "Phone Number", value: phone, textColor: textColor, subTextColor: subTextColor),
                        const Divider(height: 1),
                        _infoTile(label: "Email", value: email, textColor: textColor, subTextColor: subTextColor),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (role.isNotEmpty) _buildInviteCard(cardColor, textColor, subTextColor ?? Colors.grey),
                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }

  Widget _infoTile({
    required String label,
    required String value,
    required Color textColor,
    required Color subTextColor,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      title: Text(label, style: GoogleFonts.poppins(fontSize: 13, color: subTextColor)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6.0),
        child: Text(
          value.isNotEmpty ? value : "Not set",
          style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500, color: textColor),
        ),
      ),
    );
  }
}
