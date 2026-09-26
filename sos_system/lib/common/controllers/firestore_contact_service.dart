// lib/services/firestore_contact_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreContactService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Link Guardian <-> Child contacts when a request is accepted.
  /// Writes emergency_contacts for both users.
  ///
  /// NOTE:
  /// - The app's chat list UI now reads from emergency_contacts, so we don't
  ///   create a separate `chat_list` collection anymore.
  Future<void> linkGuardianAndChildContacts({
    required String childEmail,
    required String guardianEmail,
    required String relationship,
    required String childName,
    required String guardianName,
    required String guardianMobile,
    required String guardianUid,
    String childMobile = '',
    String childUid = '',
    bool isPrimary = false,
  }) async {
    final batch = _firestore.batch();

    final normalizedChildEmail = childEmail.trim().toLowerCase();
    final normalizedGuardianEmail = guardianEmail.trim().toLowerCase();

    // Add Guardian in Child's emergency_contacts
    final childEmergencyRef = _firestore
        .collection('Child')
        .doc(normalizedChildEmail)
        .collection('emergency_contacts')
        .doc(normalizedGuardianEmail);

    batch.set(childEmergencyRef, {
      'name': guardianName,
      'email': normalizedGuardianEmail,
      'mobile': guardianMobile ?? '',
      'uid': guardianUid ?? '',
      'relationship': relationship,
      'role': 'Guardian',
      'isPrimary': isPrimary,
      'addedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Add Child in Guardian's emergency_contacts (use provided childMobile/childUid when available)
    final guardianEmergencyRef = _firestore
        .collection('Guardian')
        .doc(normalizedGuardianEmail)
        .collection('emergency_contacts')
        .doc(normalizedChildEmail);

    batch.set(guardianEmergencyRef, {
      'name': childName,
      'email': normalizedChildEmail,
      // Use actual child mobile/uid when available (they should be passed from notification handlers)
      'mobile': childMobile ?? '',
      'uid': childUid ?? '',
      'relationship': relationship,
      'role': 'Child',
      'isPrimary': false,
      'addedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
  }
}
