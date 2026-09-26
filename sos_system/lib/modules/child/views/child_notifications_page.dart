// lib/modules/child/views/child_notifications_page.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sos_system/common/controllers/firestore_contact_service.dart';
import 'package:sos_system/common/views/custom_appbar.dart';
import 'package:sos_system/common/views/custom_snackbar.dart';
import 'package:sos_system/modules/auth/controllers/shared_preference_data.dart';

/// Child notifications page: combined view of:
/// - sent_requests (child -> guardian)  <- sender sees Cancel
/// - requests (guardian -> child)      <- receiver sees Accept/Reject
class ChildNotificationsPage extends StatefulWidget {
  const ChildNotificationsPage({super.key});

  @override
  State<ChildNotificationsPage> createState() => _ChildNotificationsPageState();
}

class _ChildNotificationsPageState extends State<ChildNotificationsPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SharedPreferenceData _prefs = SharedPreferenceData();
  final FirestoreContactService _contactService = FirestoreContactService();

  String childEmail = '';
  bool _loading = true;

  late final StreamController<List<QueryDocumentSnapshot>> _combinedController;
  StreamSubscription<QuerySnapshot>? _receivedSub; // guardian -> child (Child/{email}/requests)
  StreamSubscription<QuerySnapshot>? _sentSub; // child -> guardian (Child/{email}/sent_requests)

  List<QueryDocumentSnapshot> _receivedDocs = [];
  List<QueryDocumentSnapshot> _sentDocs = [];

  @override
  void initState() {
    super.initState();
    _initChildEmail();
    _combinedController = StreamController<List<QueryDocumentSnapshot>>.broadcast(
      onListen: _startListening,
      onCancel: _cancelListening,
    );
  }

  Future<void> _initChildEmail() async {
    await _prefs.getSharedPreferenceData();
    setState(() {
      childEmail = _prefs.email.isNotEmpty ? _prefs.email : (_auth.currentUser?.email ?? '');
      _loading = false;
    });
  }

  void _startListening() {
    if (childEmail.isEmpty) return;

    final receivedRef = _firestore
        .collection('Child')
        .doc(childEmail)
        .collection('requests')
        .orderBy('sentAt', descending: true);
    final sentRef = _firestore
        .collection('Child')
        .doc(childEmail)
        .collection('sent_requests')
        .orderBy('sentAt', descending: true);

    _receivedSub = receivedRef.snapshots().listen((snap) {
      _receivedDocs = snap.docs;
      _emitCombined();
    }, onError: (e) {
      // ignore: avoid_print
      print('Child received stream error: $e');
    });

    _sentSub = sentRef.snapshots().listen((snap) {
      _sentDocs = snap.docs;
      _emitCombined();
    }, onError: (e) {
      // ignore: avoid_print
      print('Child sent stream error: $e');
    });
  }

  void _cancelListening() {
    _receivedSub?.cancel();
    _sentSub?.cancel();
    _receivedSub = null;
    _sentSub = null;
  }

  void _emitCombined() {
    final combined = <QueryDocumentSnapshot>[];
    combined.addAll(_receivedDocs);
    combined.addAll(_sentDocs);

    combined.sort((a, b) {
      final aMap = a.data() as Map<String, dynamic>? ?? {};
      final bMap = b.data() as Map<String, dynamic>? ?? {};
      final aTs = aMap['sentAt'] as Timestamp?;
      final bTs = bMap['sentAt'] as Timestamp?;
      final aMillis = aTs?.millisecondsSinceEpoch ?? 0;
      final bMillis = bTs?.millisecondsSinceEpoch ?? 0;
      return bMillis.compareTo(aMillis);
    });

    if (!_combinedController.isClosed) _combinedController.add(combined);
  }

  @override
  void dispose() {
    _cancelListening();
    _combinedController.close();
    super.dispose();
  }

  // ------------------ Actions ------------------

  /// Child cancels a sent request (child -> guardian)
  /// - delete Guardian/{guardianEmail}/requests/{requestId} if exists
  /// - update Child/{childEmail}/sent_requests/{requestId} -> status:canceled
  Future<void> _cancelSentRequest(DocumentSnapshot sentDoc) async {
    try {
      final data = sentDoc.data() as Map<String, dynamic>? ?? {};
      final guardianEmail = (data['guardianEmail'] ?? '').toString().trim();
      final requestId = sentDoc.id;

      if (guardianEmail.isEmpty) {
        CustomSnackbar().showSnackBar(
          context,
          "Guardian email missing for this sent request.",
        );
        return;
      }

      final guardReqRef = _firestore
          .collection('Guardian')
          .doc(guardianEmail)
          .collection('requests')
          .doc(requestId);
      final guardReqSnap = await guardReqRef.get();
      if (guardReqSnap.exists) {
        await guardReqRef.delete();
      }

      final childReqRef = _firestore
          .collection('Child')
          .doc(childEmail)
          .collection('sent_requests')
          .doc(requestId);
      final childReqSnap = await childReqRef.get();
      if (childReqSnap.exists) {
        await childReqRef.update({
          'status': 'canceled',
          'canceledAt': FieldValue.serverTimestamp(),
        });
      } else {
        await childReqRef.set({
          'guardianEmail': guardianEmail,
          'status': 'canceled',
          'canceledAt': FieldValue.serverTimestamp(),
          'note': 'Canceled by child; mirror missing, created.',
        }, SetOptions(merge: true));
      }

      CustomSnackbar().showSnackBar(context, "Request canceled.");
    } catch (e) {
      CustomSnackbar().showSnackBar(context, "Failed to cancel request: $e");
    }
  }

  /// Child accepts a request sent by guardian
  /// - add guardian into Child/{childEmail}/emergency_contacts
  /// - add child into Guardian/{guardianEmail}/emergency_contacts
  /// - update Child/{childEmail}/requests/{requestId} -> accepted
  /// - update Guardian/{guardianEmail}/sent_requests/{requestId} -> accepted
  /// - add Guardian/{guardianEmail}/children mirror (unchanged)
  Future<void> _acceptReceivedRequest(DocumentSnapshot reqDoc) async {
    try {
      final raw = reqDoc.data();
      if (raw == null) {
        CustomSnackbar().showSnackBar(context, "Request data empty.");
        return;
      }
      final data = Map<String, dynamic>.from(raw as Map);

      final guardianEmail = (data['guardianEmail'] ?? '').toString().trim();
      final relationship = (data['relationship'] ?? '').toString();
      final requestId = reqDoc.id;
      final isPrimary = (data['isPrimaryRequest'] ?? false) as bool;
      final childNameFromReq = (data['childName'] ?? '').toString();

      if (guardianEmail.isEmpty) {
        CustomSnackbar().showSnackBar(context, "Guardian email missing in request.");
        return;
      }
      if (childEmail.isEmpty) {
        CustomSnackbar().showSnackBar(context, "Child not identified. Please login again.");
        return;
      }

      // Guardian profile
      final guardDocSnap = await _firestore.collection('Guardian').doc(guardianEmail).get();
      final guardData = guardDocSnap.exists ? (guardDocSnap.data() ?? {}) : <String, dynamic>{};
      final guardianName = (guardData['name'] ?? '').toString();
      final guardianMobile = (guardData['mobile'] ?? '').toString();
      final guardianUid = (guardData['uid'] ?? '').toString();

      // Child profile (to create reciprocal entry under Guardian/emergency_contacts)
      final childProfileSnap = await _firestore.collection('Child').doc(childEmail).get();
      final childData = childProfileSnap.data() ?? {};
      final childUid = (childData['uid'] ?? '').toString();
      final childMobile = (childData['mobile'] ?? '').toString();
      String childName = childNameFromReq.isNotEmpty ? childNameFromReq : (childData['name'] ?? '').toString();

      // Primary flag for child side
      final primaryQuery = await _firestore
          .collection('Child')
          .doc(childEmail)
          .collection('emergency_contacts')
          .where('isPrimary', isEqualTo: true)
          .limit(1)
          .get();
      final willBePrimary = isPrimary && primaryQuery.docs.isEmpty;

      // Use helper to create both-side contacts + chat entries
      await _contactService.linkGuardianAndChildContacts(
        childEmail: childEmail,
        guardianEmail: guardianEmail,
        relationship: relationship,
        childName: childName,
        guardianName: guardianName,
        guardianMobile: guardianMobile,
        guardianUid: guardianUid,
        // pass child's mobile/uid so guardian mirror has accurate data
        childMobile: childMobile,
        childUid: childUid,
        isPrimary: willBePrimary,
      );


      // 3) Update child's request to accepted (batch)
      final batch = _firestore.batch();

      final childReqRef = reqDoc.reference;
      batch.update(childReqRef, {
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
        'acceptedBy': childEmail,
      });

      // 4) Update guardian's mirror sent_requests doc
      final guardianSentRef = _firestore.collection('Guardian').doc(guardianEmail).collection('sent_requests').doc(requestId);
      batch.set(guardianSentRef, {
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
        'acceptedBy': childEmail,
      }, SetOptions(merge: true));

      // 5) Optional: add guardian->children entry (unchanged)
      final guardianChildRef = _firestore.collection('Guardian').doc(guardianEmail).collection('children').doc(childEmail);
      batch.set(guardianChildRef, {
        'name': childName,
        'email': childEmail,
        'relationship': relationship,
        'addedAt': FieldValue.serverTimestamp(),
        'requestId': requestId,
      }, SetOptions(merge: true));

      await batch.commit();
      CustomSnackbar().showSnackBar(context, "Request accepted. Contacts added on both sides.");
    } catch (e, st) {
      // ignore: avoid_print
      print("Failed to accept guardian request: $e\n$st");
      CustomSnackbar().showSnackBar(context, "Failed to accept request: $e");
    }
  }

  /// Child rejects a received guardian request
  Future<void> _rejectReceivedRequest(DocumentSnapshot reqDoc) async {
    try {
      final raw = reqDoc.data();
      if (raw == null) {
        CustomSnackbar().showSnackBar(context, "Request data empty.");
        return;
      }
      final data = Map<String, dynamic>.from(raw as Map);
      final guardianEmail = (data['guardianEmail'] ?? '').toString().trim();
      final requestId = reqDoc.id;

      if (guardianEmail.isEmpty) {
        CustomSnackbar().showSnackBar(context, "Guardian email missing.");
        return;
      }

      final batch = _firestore.batch();

      // update child's request doc
      final childReqRef = reqDoc.reference;
      batch.update(childReqRef, {
        'status': 'rejected',
        'rejectedAt': FieldValue.serverTimestamp(),
        'rejectedBy': childEmail,
      });

      // update guardian mirror
      final guardianSentRef = _firestore.collection('Guardian').doc(guardianEmail).collection('sent_requests').doc(requestId);
      batch.set(guardianSentRef, {
        'status': 'rejected',
        'rejectedAt': FieldValue.serverTimestamp(),
        'rejectedBy': childEmail,
      }, SetOptions(merge: true));

      await batch.commit();
      CustomSnackbar().showSnackBar(context, "Request rejected.");
    } catch (e, st) {
      // ignore: avoid_print
      print("Failed to reject request: $e\n$st");
      CustomSnackbar().showSnackBar(context, "Failed to reject request: $e");
    }
  }

  // ------------------ UI helpers ------------------

  String _formatTimestamp(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    return "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  Widget _buildReceivedRequestCard(
    DocumentSnapshot doc,
    double screenWidth,
    double titleFontSize,
    double nameFontSize,
    Color cardColor,
    Color textColor,
    Color subTextColor,
  ) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final guardianEmail = (data['guardianEmail'] ?? '').toString().trim();
    final guardianName = (data['guardianName'] ?? data['name'] ?? '').toString().trim();
    final relationship = (data['relationship'] ?? '').toString();
    final status = (data['status'] ?? 'pending').toString();
    final sentAt = data['sentAt'] as Timestamp?;
    final isPrimary = (data['isPrimaryRequest'] ?? false) as bool;

    Widget buildContent(String displayGuardianName) {
      final nameToShow = displayGuardianName.isNotEmpty ? displayGuardianName : (guardianEmail.isNotEmpty ? guardianEmail : 'Unknown Guardian');

      Color statusColor;
      String statusLabel;
      if (status == 'pending') {
        statusColor = Colors.orange;
        statusLabel = 'Pending';
      } else if (status == 'accepted') {
        statusColor = Colors.green;
        statusLabel = 'Accepted';
      } else if (status == 'rejected') {
        statusColor = Colors.red;
        statusLabel = 'Rejected';
      } else if (status == 'canceled') {
        statusColor = Colors.red;
        statusLabel = 'Canceled';
      } else {
        statusColor = Colors.grey;
        statusLabel = status;
      }

      return Container(
        padding: EdgeInsets.all((screenWidth * 0.035).clamp(12.0, 18.0)),
        decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(nameToShow, style: GoogleFonts.poppins(fontSize: nameFontSize, fontWeight: FontWeight.w700, color: textColor)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: statusColor.withOpacity(0.12), borderRadius: BorderRadius.circular(16)),
              child: Text(statusLabel, style: GoogleFonts.poppins(fontSize: titleFontSize - 1, color: statusColor, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 8),
          if (guardianEmail.isNotEmpty) Text("Email: $guardianEmail", style: GoogleFonts.poppins(color: subTextColor)),
          if (relationship.isNotEmpty) ...[const SizedBox(height: 6), Text("Relationship: $relationship", style: GoogleFonts.poppins(color: subTextColor))],
          if (sentAt != null) ...[const SizedBox(height: 6), Text("Sent: ${_formatTimestamp(sentAt)}", style: GoogleFonts.poppins(color: subTextColor, fontSize: 12))],
          const SizedBox(height: 12),
          if (status == 'pending')
            Wrap(spacing: 10, runSpacing: 8, children: [
              ElevatedButton(
                onPressed: () => _acceptReceivedRequest(doc),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: EdgeInsets.symmetric(horizontal: (screenWidth * 0.04).clamp(12.0, 20.0), vertical: 12)),
                child: Text("Accept", style: GoogleFonts.poppins(fontSize: titleFontSize - 1, color: Colors.white)),
              ),
              OutlinedButton(
                onPressed: () => _rejectReceivedRequest(doc),
                style: OutlinedButton.styleFrom(padding: EdgeInsets.symmetric(horizontal: (screenWidth * 0.04).clamp(12.0, 20.0), vertical: 12)),
                child: Text("Reject", style: GoogleFonts.poppins(fontSize: titleFontSize - 1)),
              ),
            ])
          else
            Text("Request $status", style: GoogleFonts.poppins(color: subTextColor))
        ]),
      );
    }

    return buildContent(guardianName);
  }

  Widget _buildSentRequestCard(
    DocumentSnapshot doc,
    double screenWidth,
    double titleFontSize,
    double nameFontSize,
    Color cardColor,
    Color textColor,
    Color subTextColor,
  ) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final guardianEmail = (data['guardianEmail'] ?? '').toString().trim();
    final guardianName = (data['guardianName'] ?? data['name'] ?? '').toString().trim();
    final relationship = (data['relationship'] ?? '').toString();
    final status = (data['status'] ?? 'pending').toString();
    final sentAt = data['sentAt'] as Timestamp?;
    final canceledAt = data['canceledAt'] as Timestamp?;
    final acceptedAt = data['acceptedAt'] as Timestamp?;
    final rejectedAt = data['rejectedAt'] as Timestamp?;

    Color statusColor;
    String statusLabel;
    if (status == 'pending') {
      statusColor = Colors.orange;
      statusLabel = 'Pending';
    } else if (status == 'accepted') {
      statusColor = Colors.green;
      statusLabel = 'Accepted';
    } else if (status == 'rejected') {
      statusColor = Colors.red;
      statusLabel = 'Rejected';
    } else if (status == 'canceled') {
      statusColor = Colors.red;
      statusLabel = 'Canceled';
    } else {
      statusColor = Colors.grey;
      statusLabel = status;
    }

    Widget buildContent(String displayGuardianName) {
      final displayName = displayGuardianName.isNotEmpty ? displayGuardianName : (guardianEmail.isNotEmpty ? guardianEmail : 'Unknown Guardian');

      return Container(
        padding: EdgeInsets.all((screenWidth * 0.035).clamp(12.0, 18.0)),
        decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(displayName, style: GoogleFonts.poppins(fontSize: nameFontSize, fontWeight: FontWeight.w700, color: textColor)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: statusColor.withOpacity(0.12), borderRadius: BorderRadius.circular(16)),
              child: Text(statusLabel, style: GoogleFonts.poppins(fontSize: titleFontSize - 1, color: statusColor, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 8),
          if (guardianEmail.isNotEmpty) Text("Email: $guardianEmail", style: GoogleFonts.poppins(color: subTextColor)),
          if (relationship.isNotEmpty) ...[const SizedBox(height: 6), Text("Relationship: $relationship", style: GoogleFonts.poppins(color: subTextColor))],
          if (sentAt != null) ...[const SizedBox(height: 6), Text("Sent: ${_formatTimestamp(sentAt)}", style: GoogleFonts.poppins(color: subTextColor, fontSize: 12))],
          if (acceptedAt != null) ...[Text("Accepted: ${_formatTimestamp(acceptedAt)}", style: GoogleFonts.poppins(color: subTextColor, fontSize: 12))],
          if (rejectedAt != null) ...[Text("Rejected: ${_formatTimestamp(rejectedAt)}", style: GoogleFonts.poppins(color: subTextColor, fontSize: 12))],
          if (canceledAt != null) ...[Text("Canceled: ${_formatTimestamp(canceledAt)}", style: GoogleFonts.poppins(color: subTextColor, fontSize: 12))],
          const SizedBox(height: 12),
          if (status == 'pending')
            OutlinedButton(
              onPressed: () => _cancelSentRequest(doc),
              style: OutlinedButton.styleFrom(padding: EdgeInsets.symmetric(horizontal: (screenWidth * 0.04).clamp(12.0, 20.0), vertical: 12)),
              child: Text("Cancel Request", style: GoogleFonts.poppins(fontSize: titleFontSize - 1)),
            )
        ]),
      );
    }

    return buildContent(guardianName);
  }

  // ------------------ Build ------------------

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenWidth = mq.size.width;
    final horizontalPadding = (screenWidth * 0.04).clamp(12.0, 24.0);
    final verticalPadding = (mq.size.height * 0.02).clamp(8.0, 20.0);
    final titleFontSize = (screenWidth < 360) ? 14.0 : 16.0;
    final nameFontSize = (screenWidth < 360) ? 15.0 : 16.0;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    final cardColor = Theme.of(context).cardColor;
    final textColor = isDark ? Colors.white : Colors.black;
    final subTextColor = isDark ? Colors.grey[400] : Colors.grey[700];

    if (_loading) {
      return Scaffold(appBar: const CustomAppBar(title: "Requests"), body: const Center(child: CircularProgressIndicator()));
    }

    if (childEmail.isEmpty) {
      return Scaffold(
        appBar: const CustomAppBar(title: "Requests"),
        body: Center(child: Text("No requests.", style: TextStyle(color: textColor))),
      );
    }

    return Scaffold(
      appBar: const CustomAppBar(title: "Notifications"),
      backgroundColor: bgColor,
      body: StreamBuilder<List<QueryDocumentSnapshot>>(
        stream: _combinedController.stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data ?? [];

          if (docs.isEmpty) return Center(child: Text("No requests.", style: TextStyle(color: subTextColor)));

          return ListView.separated(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
            itemCount: docs.length,
            separatorBuilder: (_, __) => SizedBox(height: verticalPadding),
            itemBuilder: (context, index) {
              final doc = docs[index];

              // robust classification using the collection id (parent collection)
              final collectionId = doc.reference.parent.id.toLowerCase();

              final data = doc.data() as Map<String, dynamic>? ?? {};

              if (collectionId == 'requests') {
                // guardian -> child (received)
                return _buildReceivedRequestCard(doc, screenWidth, titleFontSize, nameFontSize, cardColor, textColor, subTextColor!);
              } else if (collectionId == 'sent_requests') {
                // child -> guardian (sent)
                return _buildSentRequestCard(doc, screenWidth, titleFontSize, nameFontSize, cardColor, textColor, subTextColor!);
              } else {
                // fallback (rare)
                final id = doc.id;
                return Container(
                  padding: EdgeInsets.all((screenWidth * 0.035).clamp(12.0, 18.0)),
                  decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text("Request: $id", style: GoogleFonts.poppins(fontSize: nameFontSize, fontWeight: FontWeight.w700, color: textColor)),
                    const SizedBox(height: 6),
                    Text(data.toString(), style: GoogleFonts.poppins(color: subTextColor)),
                  ]),
                );
              }
            },
          );
        },
      ),
    );
  }
}
