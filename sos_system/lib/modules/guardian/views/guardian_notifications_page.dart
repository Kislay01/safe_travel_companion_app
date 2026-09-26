// lib/modules/guardian/views/guardian_notifications_page.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sos_system/common/controllers/firestore_contact_service.dart';
import 'package:sos_system/common/views/custom_appbar.dart';
import 'package:sos_system/common/views/custom_snackbar.dart';

/// Guardian notifications page: combined (received + sent) realtime list.
/// Received = Child -> Guardian (actionable: Accept / Reject)
/// Sent     = Guardian -> Child (actionable for sender: Cancel)
class GuardianNotificationsPage extends StatefulWidget {
  const GuardianNotificationsPage({super.key});

  @override
  State<GuardianNotificationsPage> createState() => _GuardianNotificationsPageState();
}

class _GuardianNotificationsPageState extends State<GuardianNotificationsPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirestoreContactService _contactService = FirestoreContactService();

  String guardianEmail = '';
  bool loading = true;

  late final StreamController<List<QueryDocumentSnapshot>> _combinedController;
  StreamSubscription<QuerySnapshot>? _receivedSub;
  StreamSubscription<QuerySnapshot>? _sentSub;

  List<QueryDocumentSnapshot> _receivedDocs = [];
  List<QueryDocumentSnapshot> _sentDocs = [];

  @override
  void initState() {
    super.initState();
    final user = _auth.currentUser;
    guardianEmail = user?.email ?? '';
    loading = false;

    _combinedController = StreamController<List<QueryDocumentSnapshot>>.broadcast(
      onListen: _startListening,
      onCancel: _cancelListening,
    );
  }

  void _startListening() {
    if (guardianEmail.isEmpty) return;

    final receivedRequestsRef = _firestore
        .collection('Guardian')
        .doc(guardianEmail)
        .collection('requests')
        .orderBy('sentAt', descending: true);

    final sentRequestsRef = _firestore
        .collection('Guardian')
        .doc(guardianEmail)
        .collection('sent_requests')
        .orderBy('sentAt', descending: true);

    _receivedSub = receivedRequestsRef.snapshots().listen((snap) {
      _receivedDocs = snap.docs;
      _emitCombined();
    }, onError: (e) {
      // ignore: avoid_print
      print('Received stream error: $e');
    });

    _sentSub = sentRequestsRef.snapshots().listen((snap) {
      _sentDocs = snap.docs;
      _emitCombined();
    }, onError: (e) {
      // ignore: avoid_print
      print('Sent stream error: $e');
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

  /// Accept a request that was SENT BY A CHILD to this guardian:
  /// - add guardian to Child/{childEmail}/emergency_contacts
  /// - add child to Guardian/{guardianEmail}/emergency_contacts
  /// - update Guardian/{guardianEmail}/requests/{requestId} -> accepted
  /// - update Child/{childEmail}/sent_requests/{requestId} -> accepted
  /// - add Guardian/{guardianEmail}/children/{childEmail}
  /// - create Child notification
  Future<void> _acceptReceivedRequest(DocumentSnapshot reqDoc) async {
    try {
      final raw = reqDoc.data();
      if (raw == null) {
        CustomSnackbar().showSnackBar(context, "Request data is empty.");
        return;
      }
      final data = Map<String, dynamic>.from(raw as Map);

      final childEmail = (data['childEmail'] ?? '').toString().trim();
      final relationship = (data['relationship'] ?? '').toString();
      final requestId = reqDoc.id;
      final isPrimaryRequest = data['isPrimaryRequest'] == true;
      final childNameFromReq = (data['childName'] ?? '').toString();

      if (guardianEmail.isEmpty) {
        CustomSnackbar().showSnackBar(context, "Guardian email not available.");
        return;
      }
      if (childEmail.isEmpty) {
        CustomSnackbar().showSnackBar(context, "Child email missing in request.");
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

      // Primary check for child side
      final primaryQuery = await _firestore
          .collection('Child')
          .doc(childEmail)
          .collection('emergency_contacts')
          .where('isPrimary', isEqualTo: true)
          .limit(1)
          .get();
      final willBePrimary = isPrimaryRequest && primaryQuery.docs.isEmpty;

      // Use helper to add emergency contacts and chat entries on both sides
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

      // Continue with request status updates and mirrors (in a separate batch)
      final batch = _firestore.batch();

      // update guardian request status
      final guardianReqRef = reqDoc.reference;
      batch.update(guardianReqRef, {
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
        'acceptedBy': guardianEmail,
      });

      // update child's mirror sent_requests
      final childSentReqRef = _firestore.collection('Child').doc(childEmail).collection('sent_requests').doc(requestId);
      batch.set(childSentReqRef, {
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
        'acceptedBy': guardianEmail,
      }, SetOptions(merge: true));

      // add child into guardian's children list (mirror)
      final guardianChildRef = _firestore.collection('Guardian').doc(guardianEmail).collection('children').doc(childEmail);
      batch.set(guardianChildRef, {
        'name': childName,
        'email': childEmail,
        'relationship': relationship,
        'addedAt': FieldValue.serverTimestamp(),
        'requestId': requestId,
      }, SetOptions(merge: true));

      // optional child notification
      final childNotifRef = _firestore.collection('Child').doc(childEmail).collection('notifications').doc();
      batch.set(childNotifRef, {
        'type': 'guardian_accepted',
        'title': 'Guardian Accepted',
        'message': '${guardianName.isNotEmpty ? guardianName : guardianEmail} accepted your guardian request',
        'timestamp': FieldValue.serverTimestamp(),
        'requestId': requestId,
      });

      await batch.commit();
      CustomSnackbar().showSnackBar(context, "Request accepted. Contacts added on both sides.");
    } catch (e, st) {
      // ignore: avoid_print
      print("Failed to accept request: $e\n$st");
      CustomSnackbar().showSnackBar(context, "Failed to accept request: $e");
    }
  }

  /// Reject a received request (child -> guardian)
  Future<void> _rejectReceivedRequest(DocumentSnapshot reqDoc) async {
    try {
      final raw = reqDoc.data();
      if (raw == null) {
        CustomSnackbar().showSnackBar(context, "Request data is empty.");
        return;
      }
      final data = Map<String, dynamic>.from(raw as Map);

      final childEmail = (data['childEmail'] ?? '').toString().trim();
      final requestId = reqDoc.id;

      if (guardianEmail.isEmpty) {
        CustomSnackbar().showSnackBar(context, "Guardian email not available.");
        return;
      }
      if (childEmail.isEmpty) {
        CustomSnackbar().showSnackBar(context, "Child email missing in request.");
        return;
      }

      final batch = _firestore.batch();

      final guardianReqRef = reqDoc.reference;
      batch.update(guardianReqRef, {
        'status': 'rejected',
        'rejectedAt': FieldValue.serverTimestamp(),
        'rejectedBy': guardianEmail,
      });

      final childSentReqRef = _firestore.collection('Child').doc(childEmail).collection('sent_requests').doc(requestId);
      batch.set(childSentReqRef, {
        'status': 'rejected',
        'rejectedAt': FieldValue.serverTimestamp(),
        'rejectedBy': guardianEmail,
      }, SetOptions(merge: true));

      final childNotifRef = _firestore.collection('Child').doc(childEmail).collection('notifications').doc();
      batch.set(childNotifRef, {
        'type': 'guardian_rejected',
        'title': 'Request Rejected',
        'message': 'Your guardian request was rejected',
        'timestamp': FieldValue.serverTimestamp(),
        'requestId': requestId,
      });

      await batch.commit();
      CustomSnackbar().showSnackBar(context, "Request rejected.");
    } catch (e, st) {
      // ignore: avoid_print
      print("Failed to reject request: $e\n$st");
      CustomSnackbar().showSnackBar(context, "Failed to reject request: $e");
    }
  }

  /// Cancel a sent request (guardian -> child)
  Future<void> _cancelSentRequest(DocumentSnapshot sentDoc) async {
    try {
      final data = sentDoc.data() as Map<String, dynamic>? ?? {};
      final childEmail = (data['childEmail'] ?? '').toString().trim();
      final requestId = sentDoc.id;

      if (childEmail.isEmpty) {
        CustomSnackbar().showSnackBar(context, "Child email missing for this sent request.");
        return;
      }

      // Delete child's request doc if exists
      final childReqRef = _firestore.collection('Child').doc(childEmail).collection('requests').doc(requestId);
      final childReqSnap = await childReqRef.get();
      if (childReqSnap.exists) {
        await childReqRef.delete();
      }

      // Update guardian's sent_requests mirror to canceled
      final guardianSentRef = _firestore.collection('Guardian').doc(guardianEmail).collection('sent_requests').doc(requestId);
      final guardianSentSnap = await guardianSentRef.get();
      if (guardianSentSnap.exists) {
        await guardianSentRef.update({
          'status': 'canceled',
          'canceledAt': FieldValue.serverTimestamp(),
        });
      } else {
        await guardianSentRef.set({
          'childEmail': childEmail,
          'status': 'canceled',
          'canceledAt': FieldValue.serverTimestamp(),
          'note': 'Canceled by guardian; mirror was missing, created by system.',
        }, SetOptions(merge: true));
      }

      CustomSnackbar().showSnackBar(context, "Request canceled.");
    } catch (e) {
      CustomSnackbar().showSnackBar(context, "Failed to cancel request: $e");
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
    final data = doc.data() as Map<String, dynamic>;
    final rawChildName = (data['childName'] ?? data['name'] ?? '').toString().trim();
    final relationship = data['relationship'] ?? '';
    final status = (data['status'] ?? 'pending').toString();
    final childEmail = (data['childEmail'] ?? '').toString().trim();
    final sentAt = data['sentAt'] as Timestamp?;
    final isPrimaryRequest = (data['isPrimaryRequest'] ?? false) as bool;

    final showPrimaryTopChip = isPrimaryRequest && status == 'pending';

    Widget buildContent(String displayChildName) {
      final childNameToShow = displayChildName.isNotEmpty ? displayChildName : 'Unknown';
      return Container(
        padding: EdgeInsets.all((screenWidth * 0.035).clamp(12.0, 18.0)),
        decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(childNameToShow, style: GoogleFonts.poppins(fontSize: nameFontSize, fontWeight: FontWeight.w700, color: textColor)),
            ),
            if (showPrimaryTopChip)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(16)),
                child: Text('Primary request', style: GoogleFonts.poppins(fontSize: titleFontSize - 1, color: Colors.black, fontWeight: FontWeight.w600)),
              )
            else
              Text(
                status.toUpperCase(),
                style: TextStyle(
                  color: status == 'pending' ? Colors.orange : (status == 'accepted' ? Colors.green : Colors.red),
                  fontWeight: FontWeight.w600,
                  fontSize: titleFontSize - 1,
                ),
              ),
          ]),
          const SizedBox(height: 8),
          if (childEmail.isNotEmpty) Text("Email: $childEmail", style: GoogleFonts.poppins(color: subTextColor)),
          if (relationship.toString().isNotEmpty) ...[const SizedBox(height: 6), Text("Relationship: $relationship", style: GoogleFonts.poppins(color: subTextColor))],
          const SizedBox(height: 12),
          if (sentAt != null) Text("Sent: ${_formatTimestamp(sentAt)}", style: GoogleFonts.poppins(fontSize: 12, color: subTextColor)),
          const SizedBox(height: 12),
          if (status == 'pending')
            Wrap(spacing: 10, runSpacing: 8, children: [
              ElevatedButton(
                onPressed: () => _acceptReceivedRequest(doc),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: EdgeInsets.symmetric(horizontal: (screenWidth * 0.04).clamp(12.0, 20.0), vertical: 12),
                ),
                child: Text("Accept", style: GoogleFonts.poppins(fontSize: titleFontSize - 1, color: Colors.white)),
              ),
              OutlinedButton(
                onPressed: () => _rejectReceivedRequest(doc),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: (screenWidth * 0.04).clamp(12.0, 20.0), vertical: 12),
                ),
                child: Text("Reject", style: GoogleFonts.poppins(fontSize: titleFontSize - 1)),
              )
            ])
          else
            Text("Request $status", style: GoogleFonts.poppins(color: subTextColor))
        ]),
      );
    }

    if (rawChildName.isNotEmpty) return buildContent(rawChildName);
    if (childEmail.isEmpty) return buildContent('');
    return FutureBuilder<DocumentSnapshot>(
      future: _firestore.collection('Child').doc(childEmail).get(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return buildContent('');
        if (snap.hasData && snap.data!.exists) {
          final childDoc = snap.data!.data() as Map<String, dynamic>? ?? {};
          final fetchedName = (childDoc['name'] ?? childDoc['fullName'] ?? '').toString().trim();
          return buildContent(fetchedName);
        }
        return buildContent('');
      },
    );
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
    final childEmail = (data['childEmail'] ?? data['email'] ?? '').toString().trim();
    final childName = (data['childName'] ?? data['name'] ?? '').toString().trim();
    final relationship = (data['relationship'] ?? '').toString();
    final status = (data['status'] ?? 'pending').toString();
    final sentAt = data['sentAt'] as Timestamp?;
    final respondedAt = (data['acceptedAt'] ?? data['rejectedAt'] ?? data['canceledAt']) as Timestamp?;
    final requestId = doc.id;

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

    Widget buildContent(String displayChildName) {
      final displayName = displayChildName.isNotEmpty ? displayChildName : (childEmail.isNotEmpty ? childEmail : 'Unknown Child');
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
          if (childEmail.isNotEmpty) Text("Email: $childEmail", style: GoogleFonts.poppins(color: subTextColor)),
          if (relationship.isNotEmpty) ...[const SizedBox(height: 6), Text("Relationship: $relationship", style: GoogleFonts.poppins(color: subTextColor))],
          const SizedBox(height: 10),
          if (sentAt != null) Text("Sent: ${_formatTimestamp(sentAt)}", style: GoogleFonts.poppins(fontSize: 12, color: subTextColor)),
          if (respondedAt != null) Text("Updated: ${_formatTimestamp(respondedAt)}", style: GoogleFonts.poppins(fontSize: 12, color: subTextColor)),
          const SizedBox(height: 12),
          if (status == 'pending')
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: () => _cancelSentRequest(doc),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: (screenWidth * 0.04).clamp(12.0, 20.0), vertical: 12),
                ),
                child: Text("Cancel Request", style: GoogleFonts.poppins(fontSize: titleFontSize - 1)),
              ),
            )
        ]),
      );
    }

    if (childName.isNotEmpty) return buildContent(childName);
    if (childEmail.isEmpty) return buildContent('');
    return FutureBuilder<DocumentSnapshot>(
      future: _firestore.collection('Child').doc(childEmail).get(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return buildContent('');
        if (snap.hasData && snap.data!.exists) {
          final childDoc = snap.data!.data() as Map<String, dynamic>? ?? {};
          final fetchedName = (childDoc['name'] ?? childDoc['fullName'] ?? '').toString().trim();
          return buildContent(fetchedName);
        }
        return buildContent('');
      },
    );
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

    if (guardianEmail.isEmpty) {
      return Scaffold(
        appBar: const CustomAppBar(title: "Requests"),
        body: Center(child: Text("No guardian signed in.", style: TextStyle(color: textColor))),
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

          if (docs.isEmpty) {
            return Center(child: Text("No requests.", style: TextStyle(color: subTextColor)));
          }

          return ListView.separated(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
            itemCount: docs.length,
            separatorBuilder: (_, __) => SizedBox(height: verticalPadding),
            itemBuilder: (context, index) {
              final doc = docs[index];

              final collectionId = doc.reference.parent.id.toLowerCase();
              if (collectionId == 'requests') {
                return _buildReceivedRequestCard(doc, screenWidth, titleFontSize, nameFontSize, cardColor, textColor, subTextColor!);
              } else if (collectionId == 'sent_requests') {
                return _buildSentRequestCard(doc, screenWidth, titleFontSize, nameFontSize, cardColor, textColor, subTextColor!);
              } else {
                final data = doc.data() as Map<String, dynamic>? ?? {};
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
