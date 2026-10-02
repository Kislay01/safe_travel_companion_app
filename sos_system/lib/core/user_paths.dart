import 'package:cloud_firestore/cloud_firestore.dart';

/// Central place for Firestore paths and the email normalisation rule.
class UserPaths {
  UserPaths._();

  static final FirebaseFirestore db = FirebaseFirestore.instance;

  static String normalize(String email) => email.trim().toLowerCase();

  static DocumentReference<Map<String, dynamic>> child(String email) =>
      db.collection('Child').doc(normalize(email));

  static DocumentReference<Map<String, dynamic>> guardian(String email) =>
      db.collection('Guardian').doc(normalize(email));

  /// Guardian emails linked to a child (doc ids of the child's emergency contacts).
  static Future<List<String>> guardiansOf(String childEmail) async {
    final snap = await child(childEmail).collection('emergency_contacts').get();
    return snap.docs.map((d) => d.id).toList();
  }

  /// Child contacts linked to a guardian.
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> childrenOf(
      String guardianEmail) async {
    final snap =
        await guardian(guardianEmail).collection('emergency_contacts').get();
    return snap.docs
        .where((d) => (d.data()['role'] ?? 'Child') == 'Child')
        .toList();
  }

  /// Writes an alert into every linked guardian's notifications feed.
  static Future<void> notifyGuardians({
    required String childEmail,
    required String type,
    required String title,
    required String body,
    Map<String, dynamic> extra = const {},
  }) async {
    final guardians = await guardiansOf(childEmail);
    if (guardians.isEmpty) return;
    final batch = db.batch();
    for (final g in guardians) {
      batch.set(guardian(g).collection('notifications').doc(), {
        'type': type,
        'title': title,
        'body': body,
        'childEmail': normalize(childEmail),
        'createdAt': FieldValue.serverTimestamp(),
        'read': false,
        ...extra,
      });
    }
    await batch.commit();
  }

  /// Writes an alert into one guardian's notifications feed.
  static Future<void> notifyGuardian({
    required String guardianEmail,
    required String childEmail,
    required String type,
    required String title,
    required String body,
    Map<String, dynamic> extra = const {},
  }) {
    return guardian(guardianEmail).collection('notifications').add({
      'type': type,
      'title': title,
      'body': body,
      'childEmail': normalize(childEmail),
      'createdAt': FieldValue.serverTimestamp(),
      'read': false,
      ...extra,
    });
  }
}
