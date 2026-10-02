import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sos_system/core/user_paths.dart';

/// Guardian → child "Are you OK?" check-ins.
/// Child/{child}/checkins/{id} {guardianEmail, guardianName, status: pending|ok|help, createdAt, respondedAt}
class CheckinService {
  CheckinService._();

  static Future<DocumentReference<Map<String, dynamic>>> send({
    required String childEmail,
    required String guardianEmail,
    required String guardianName,
  }) {
    return UserPaths.child(childEmail).collection('checkins').add({
      'guardianEmail': UserPaths.normalize(guardianEmail),
      'guardianName': guardianName,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> respond({
    required String childEmail,
    required String childName,
    required String checkinId,
    required String guardianEmail,
    required bool ok,
  }) async {
    await UserPaths.child(childEmail).collection('checkins').doc(checkinId).update({
      'status': ok ? 'ok' : 'help',
      'respondedAt': FieldValue.serverTimestamp(),
    });
    final who = childName.isNotEmpty ? childName : childEmail;
    await UserPaths.notifyGuardian(
      guardianEmail: guardianEmail,
      childEmail: childEmail,
      type: 'checkin_response',
      title: ok ? '✅ $who is OK' : '🆘 $who needs help',
      body: ok ? 'Replied to your check-in.' : 'SOS has been triggered.',
      extra: {'status': ok ? 'ok' : 'help', 'checkinId': checkinId},
    );
  }
}
