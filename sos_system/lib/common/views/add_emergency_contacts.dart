// lib/modules/child/views/add_emergency_contacts.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sos_system/common/views/custom_appbar.dart';
import 'package:sos_system/common/views/custom_snackbar.dart';
import 'package:sos_system/modules/auth/controllers/shared_preference_data.dart';

/// If [isGuardian] is false (default) the screen works as before:
///   - child enters guardian details -> request created under Guardian/{guardianEmail}/requests
/// If [isGuardian] is true the screen is used by a guardian adding a child:
///   - guardian enters child details -> request created under Child/{childEmail}/requests
class AddEmergencyContacts extends StatefulWidget {
  final bool isGuardian;
  const AddEmergencyContacts({super.key, this.isGuardian = false});

  @override
  State<AddEmergencyContacts> createState() => _AddEmergencyContactsState();
}

class _AddEmergencyContactsState extends State<AddEmergencyContacts> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController relationController = TextEditingController();
  final TextEditingController emailController = TextEditingController();

  final FocusNode _nameFocus = FocusNode();
  final FocusNode _phoneFocus = FocusNode();
  final FocusNode _relationFocus = FocusNode();
  final FocusNode _emailFocus = FocusNode();

  String _nameError = '';
  String _phoneError = '';
  String _relationError = '';
  String _emailError = '';

  static const int nameMaxLength = 50;
  static const int relationMaxLength = 30;
  static const int phoneMaxDigits = 15; // excluding leading '+'
  static const int emailMaxLength = 100;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final SharedPreferenceData _prefs = SharedPreferenceData();

  // current user info (guardian or child depending on who opened)
  String _currentUserEmail = '';
  String _currentUserUid = '';
  String _currentUserName = '';
  String _currentUserMobile = '';

  @override
  void initState() {
    super.initState();
    nameController.addListener(() => _validateField(FieldType.name));
    phoneController.addListener(() => _validateField(FieldType.phone));
    relationController.addListener(() => _validateField(FieldType.relation));
    emailController.addListener(() => _validateField(FieldType.email));
    _loadCurrentUserInfo();
  }

  Future<void> _loadCurrentUserInfo() async {
    // Load shared prefs (works for both guardian and child flows)
    await _prefs.getSharedPreferenceData();
    setState(() {
      _currentUserEmail = _prefs.email.isNotEmpty ? _prefs.email : (_auth.currentUser?.email ?? '');
      _currentUserUid = _prefs.uid.isNotEmpty ? _prefs.uid : (_auth.currentUser?.uid ?? '');
      _currentUserName = _prefs.name.isNotEmpty ? _prefs.name : (_auth.currentUser?.displayName ?? '');
      _currentUserMobile = (_prefs.mobile ?? '').toString().isNotEmpty ? (_prefs.mobile ?? '') : '';
      // Note: SharedPreferenceData might not have mobile; it's fine to be empty.
    });
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    relationController.dispose();
    emailController.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();
    _relationFocus.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  void _validateField(FieldType type) {
    setState(() {
      switch (type) {
        case FieldType.name:
          _nameError = _localNameValidator(nameController.text) ?? '';
          break;
        case FieldType.phone:
          _phoneError = _localPhoneValidator(phoneController.text) ?? '';
          break;
        case FieldType.relation:
          _relationError = _localRelationValidator(relationController.text) ?? '';
          break;
        case FieldType.email:
          _emailError = _localEmailValidator(emailController.text) ?? '';
          break;
      }
    });
  }

  String? _localNameValidator(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Please enter a name.';
    if (v.length < 2) return 'Name must be at least 2 characters.';
    if (v.length > nameMaxLength) return 'Name can be at most $nameMaxLength characters.';
    final nameRegex = RegExp(r"^[a-zA-Z\s'-]+$");
    if (!nameRegex.hasMatch(v)) return 'Name contains invalid characters.';
    return null;
  }

  String? _localPhoneValidator(String? value) {
    var v = (value ?? '').trim();
    // If guardian is adding child -> phone is required
    if (widget.isGuardian && v.isEmpty) return 'Please enter phone number.';
    if (v.isEmpty) return null; // allow empty phone when child adds guardian
    final cleaned = v.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    final phoneRegex = RegExp(r'^\+?[0-9]{7,15}$');
    if (!phoneRegex.hasMatch(cleaned)) return 'Enter valid phone (7–15 digits, optional +).';
    final digitsOnly = cleaned.replaceFirst('+', '');
    if (digitsOnly.length > phoneMaxDigits) return 'Phone number is too long.';
    return null;
  }

  String? _localRelationValidator(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return null; // optional
    if (v.length > relationMaxLength) return 'Relationship can be at most $relationMaxLength characters.';
    final relRegex = RegExp(r"^[a-zA-Z\s'-]+$");
    if (!relRegex.hasMatch(v)) return 'Relationship contains invalid characters.';
    return null;
  }

  String? _localEmailValidator(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Please enter email.';
    if (v.length > emailMaxLength) return 'Email can be at most $emailMaxLength characters.';
    final emailRegex = RegExp(r"^[\w\.\-]+@[a-zA-Z0-9\.\-]+\.[a-zA-Z]{2,}$");
    if (!emailRegex.hasMatch(v)) return 'Enter a valid email address.';
    return null;
  }

  String _normalizePhone(String raw) {
    var v = raw.trim();
    v = v.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    return v;
  }

  String _normalizeEmail(String raw) {
    return raw.trim().toLowerCase();
  }

  Future<void> _onAddPressed() async {
    // Shared validations (email must be valid, name must be present)
    final emailErr = _localEmailValidator(emailController.text);
    final nameErr = _localNameValidator(nameController.text);
    final phoneErr = _localPhoneValidator(phoneController.text);
    final relationErr = _localRelationValidator(relationController.text);

    setState(() {
      _emailError = emailErr ?? '';
      _nameError = nameErr ?? '';
      _phoneError = phoneErr ?? '';
      _relationError = relationErr ?? '';
    });

    if (emailErr != null) {
      _emailFocus.requestFocus();
      return;
    }
    if (nameErr != null) {
      _nameFocus.requestFocus();
      return;
    }
    if (phoneErr != null) {
      _phoneFocus.requestFocus();
      return;
    }
    if (relationErr != null) {
      _relationFocus.requestFocus();
      return;
    }

    // Normalize inputs
    final inputEmail = _normalizeEmail(emailController.text);
    final inputName = nameController.text.trim();
    final inputPhone = _normalizePhone(phoneController.text);
    final inputRelation = relationController.text.trim();

    if (widget.isGuardian) {
      await _guardianSendsRequestToChild(
        childEmail: inputEmail,
        childName: inputName,
        childPhone: inputPhone,
        relationship: inputRelation,
      );
    } else {
      await _childSendsRequestToGuardian(
        guardianEmail: inputEmail,
        guardianName: inputName,
        guardianPhone: inputPhone,
        relationship: inputRelation,
      );
    }
  }

  Future<void> _childSendsRequestToGuardian({
    required String guardianEmail,
    required String guardianName,
    required String guardianPhone,
    required String relationship,
  }) async {
    try {
      // Lookup guardian by email (doc id)
      final guardianDocRef = _firestore.collection('Guardian').doc(guardianEmail);
      final guardianSnapshot = await guardianDocRef.get();

      if (!guardianSnapshot.exists) {
        CustomSnackbar().showSnackBar(context, "Guardian not found with this email. Please check the email.");
        return;
      }

      final guardianData = guardianSnapshot.data() ?? {};
      final guardianUid = guardianData['uid'] ?? '';

      // load child info (from prefs or auth)
      await _prefs.getSharedPreferenceData();
      final childEmail = _prefs.email.isNotEmpty ? _prefs.email : (_auth.currentUser?.email ?? '');
      final childUid = _prefs.uid.isNotEmpty ? _prefs.uid : (_auth.currentUser?.uid ?? '');
      final childName = _prefs.name.isNotEmpty ? _prefs.name : (_auth.currentUser?.displayName ?? '');

      if (childEmail.isEmpty) {
        CustomSnackbar().showSnackBar(context, "Child not identified. Please login again.");
        return;
      }

      // check if child's emergency contacts already contain a primary
      final primaryQuery = await _firestore
          .collection('Child')
          .doc(childEmail)
          .collection('emergency_contacts')
          .where('isPrimary', isEqualTo: true)
          .limit(1)
          .get();

      final bool isPrimaryRequest = primaryQuery.docs.isEmpty;

      // check duplicate pending request from this child to this guardian (prevent duplicates)
      final duplicateQuery = await guardianDocRef
          .collection('requests')
          .where('childEmail', isEqualTo: childEmail)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();

      if (duplicateQuery.docs.isNotEmpty) {
        CustomSnackbar().showSnackBar(context, "You already have a pending request to this guardian.");
        return;
      }

      // create request under guardian document
      final requestRef = await guardianDocRef.collection('requests').add({
        'childEmail': childEmail,
        'childUid': childUid,
        'childName': childName,
        'guardianName': guardianName,
        'guardianMobile': guardianPhone,
        'relationship': relationship,
        'status': 'pending',
        'isPrimaryRequest': isPrimaryRequest,
        'sentAt': FieldValue.serverTimestamp(),
      });

      // mirror under child for auditing
      await _firestore.collection('Child').doc(childEmail).collection('sent_requests').doc(requestRef.id).set({
        'guardianEmail': guardianEmail,
        'guardianUid': guardianUid,
        'guardianName': guardianName,
        'relationship': relationship,
        'status': 'pending',
        'sentAt': FieldValue.serverTimestamp(),
      });

      CustomSnackbar().showSnackBar(context, "Request sent to guardian.");
      Navigator.pop(context);
    } catch (e) {
      CustomSnackbar().showSnackBar(context, "Failed to send request: $e");
    }
  }

  Future<void> _guardianSendsRequestToChild({
    required String childEmail,
    required String childName,
    required String childPhone,
    required String relationship,
  }) async {
    try {
      // Lookup child by email (doc id)
      final childDocRef = _firestore.collection('Child').doc(childEmail);
      final childSnapshot = await childDocRef.get();

      // 1) Ensure child exists
      if (!childSnapshot.exists) {
        CustomSnackbar().showSnackBar(context, "Child not found with this email. Please check the email.");
        return;
      }

      final childData = childSnapshot.data() ?? {};
      final childUid = childData['uid'] ?? '';

      // load guardian info (from prefs or auth)
      await _prefs.getSharedPreferenceData();
      final guardianEmail = _prefs.email.isNotEmpty ? _prefs.email : (_auth.currentUser?.email ?? '');
      final guardianUid = _prefs.uid.isNotEmpty ? _prefs.uid : (_auth.currentUser?.uid ?? '');
      final guardianName = _prefs.name.isNotEmpty ? _prefs.name : (_auth.currentUser?.displayName ?? '');
      final guardianMobile = (_prefs.mobile ?? '').toString();

      if (guardianEmail.isEmpty) {
        CustomSnackbar().showSnackBar(context, "Guardian not identified. Please login again.");
        return;
      }

      // 2) Check if guardian already in child's emergency_contacts (no need to send request)
      final existingContactsQuery = await childDocRef
          .collection('emergency_contacts')
          .where('email', isEqualTo: guardianEmail)
          .limit(1)
          .get();

      if (existingContactsQuery.docs.isNotEmpty) {
        CustomSnackbar().showSnackBar(context, "This guardian is already added to the child's emergency contacts.");
        return;
      }

      // 3) Check for an existing pending request from this guardian to this child
      final pendingReqQuery = await childDocRef
          .collection('requests')
          .where('guardianEmail', isEqualTo: guardianEmail)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();

      if (pendingReqQuery.docs.isNotEmpty) {
        CustomSnackbar().showSnackBar(context, "There is already a pending request to this child from you.");
        return;
      }

      // All checks passed — create request under child's requests collection
      final requestRef = await childDocRef.collection('requests').add({
        'guardianEmail': guardianEmail,
        'guardianUid': guardianUid,
        'guardianName': guardianName,
        'guardianMobile': guardianMobile,
        'childName': childName,
        'childUid': childUid,
        'childMobile': childPhone,
        'relationship': relationship,
        'status': 'pending',
        'sentAt': FieldValue.serverTimestamp(),
      });

      // mirror under guardian for traceability
      await _firestore
          .collection('Guardian')
          .doc(guardianEmail)
          .collection('sent_requests')
          .doc(requestRef.id)
          .set({
        'childEmail': childEmail,
        'childUid': childUid,
        'childName': childName,
        'relationship': relationship,
        'status': 'pending',
        'sentAt': FieldValue.serverTimestamp(),
      });

      CustomSnackbar().showSnackBar(context, "Request sent to child.");
      Navigator.pop(context);
    } catch (e) {
      CustomSnackbar().showSnackBar(context, "Failed to send request: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF121212) : Colors.grey[100];
    final cardColor = Theme.of(context).cardColor;
    final textColor = isDark ? Colors.white : Colors.black;
    final hintColor = isDark ? Colors.grey[400] : Colors.grey[600];
    final borderColor = isDark ? Colors.grey[700]! : Colors.grey[300]!;

    final title = widget.isGuardian ? "Add Child" : "Add Emergency Contact";
    final description = widget.isGuardian
        ? "Fill child details to send a request from guardian to child."
        : "Add a trusted contact who can be notified in case of emergency. This contact will receive alerts and updates about your safety.";

    // Field labels/hints vary by mode:
    final emailHint = widget.isGuardian ? "Child Email" : "Guardian Email";
    final nameHint = widget.isGuardian ? "Child Name" : "Contact Name";
    final phoneHint = widget.isGuardian ? "Child Phone (required)" : "Phone Number";
    final buttonText = widget.isGuardian ? "Send Request to Child" : "Send Request";

    return Scaffold(
      appBar: CustomAppBar(title: title),
      backgroundColor: backgroundColor,
      body: Padding(
        padding: const EdgeInsets.all(15),
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 10),
              Text(
                description,
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  color: textColor.withOpacity(0.9),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),

              // Email (guardianEmail when child opens, childEmail when guardian opens)
              TextField(
                controller: emailController,
                focusNode: _emailFocus,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _nameFocus.requestFocus(),
                style: GoogleFonts.poppins(fontSize: 18, color: textColor),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: cardColor,
                  hintText: emailHint,
                  hintStyle: GoogleFonts.poppins(fontSize: 18, color: hintColor),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: const BorderSide(color: Color.fromRGBO(0, 123, 255, 1.0), width: 1.5),
                  ),
                ),
                inputFormatters: [LengthLimitingTextInputFormatter(emailMaxLength)],
                keyboardType: TextInputType.emailAddress,
              ),

              if (_emailError.isNotEmpty) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_emailError, style: GoogleFonts.poppins(fontSize: 13, color: Colors.redAccent)),
                ),
              ],

              const SizedBox(height: 20),

              // Name
              TextField(
                controller: nameController,
                focusNode: _nameFocus,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _phoneFocus.requestFocus(),
                style: GoogleFonts.poppins(fontSize: 18, color: textColor),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: cardColor,
                  hintText: nameHint,
                  hintStyle: GoogleFonts.poppins(fontSize: 18, color: hintColor),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: const BorderSide(color: Color.fromRGBO(0, 123, 255, 1.0), width: 1.5),
                  ),
                ),
                inputFormatters: [LengthLimitingTextInputFormatter(nameMaxLength)],
              ),

              if (_nameError.isNotEmpty) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_nameError, style: GoogleFonts.poppins(fontSize: 13, color: Colors.redAccent)),
                ),
              ],

              const SizedBox(height: 20),

              // Phone
              TextField(
                controller: phoneController,
                focusNode: _phoneFocus,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _relationFocus.requestFocus(),
                keyboardType: TextInputType.phone,
                style: GoogleFonts.poppins(fontSize: 18, color: textColor),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: cardColor,
                  hintText: phoneHint,
                  hintStyle: GoogleFonts.poppins(fontSize: 18, color: hintColor),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: const BorderSide(color: Color.fromRGBO(0, 123, 255, 1.0), width: 1.5),
                  ),
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d\+\s\-\(\)]')),
                  LengthLimitingTextInputFormatter(phoneMaxDigits + 1),
                ],
              ),

              if (_phoneError.isNotEmpty) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_phoneError, style: GoogleFonts.poppins(fontSize: 13, color: Colors.redAccent)),
                ),
              ],

              const SizedBox(height: 20),

              // Relationship
              TextField(
                controller: relationController,
                focusNode: _relationFocus,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _onAddPressed(),
                style: GoogleFonts.poppins(fontSize: 18, color: textColor),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: cardColor,
                  hintText: "Relationship (optional)",
                  hintStyle: GoogleFonts.poppins(fontSize: 18, color: hintColor),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: const BorderSide(color: Color.fromRGBO(0, 123, 255, 1.0), width: 1.5),
                  ),
                ),
                inputFormatters: [LengthLimitingTextInputFormatter(relationMaxLength)],
              ),

              if (_relationError.isNotEmpty) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_relationError, style: GoogleFonts.poppins(fontSize: 13, color: Colors.redAccent)),
                ),
              ],

              const SizedBox(height: 40),

              ElevatedButton(
                onPressed: _onAddPressed,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 60),
                  backgroundColor: const Color.fromRGBO(0, 123, 255, 1.0),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(
                  widget.isGuardian ? "Send Request to Child" : "Send Request",
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 20, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum FieldType { name, phone, relation, email }
