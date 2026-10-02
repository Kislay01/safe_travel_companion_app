import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sos_system/common/controllers/firestore_contact_service.dart';
import 'package:sos_system/core/user_paths.dart';
import 'package:uuid/uuid.dart';

/// Invite codes: every user gets a code like TG-7K3P9A. A new user who enters
/// a code of the opposite role at sign-up is linked automatically.
/// invites/{code} {email, role, name, createdAt}
class InviteService {
  InviteService._();

  static final _db = FirebaseFirestore.instance;

  static String _newCode() =>
      'TG-${const Uuid().v4().replaceAll('-', '').substring(0, 6).toUpperCase()}';

  static String normalizeCode(String raw) {
    var c = raw.trim().toUpperCase().replaceAll(' ', '');
    if (c.isNotEmpty && !c.startsWith('TG-')) c = 'TG-${c.replaceFirst('TG', '')}';
    return c;
  }

  /// Returns the user's invite code, creating it on first use.
  static Future<String> ensureCode({
    required String email,
    required String role,
    required String name,
  }) async {
    final userRef = _db.collection(role).doc(UserPaths.normalize(email));
    final existing = (await userRef.get()).data()?['inviteCode'] as String?;
    if (existing != null && existing.isNotEmpty) return existing;

    for (var i = 0; i < 5; i++) {
      final code = _newCode();
      final inviteRef = _db.collection('invites').doc(code);
      if ((await inviteRef.get()).exists) continue;
      await inviteRef.set({
        'email': UserPaths.normalize(email),
        'role': role,
        'name': name,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await userRef.set({'inviteCode': code}, SetOptions(merge: true));
      return code;
    }
    throw Exception('Could not create an invite code. Try again.');
  }

  /// Links the current user with the owner of [rawCode]. Returns an error
  /// message, or null on success.
  static Future<String?> redeem({
    required String rawCode,
    required String myEmail,
    required String myRole,
  }) async {
    final code = normalizeCode(rawCode);
    if (code.length < 5) return 'Invalid invite code.';
    final inv = await _db.collection('invites').doc(code).get();
    final data = inv.data();
    if (data == null) return 'Invite code $code not found.';

    final inviterRole = (data['role'] ?? '').toString();
    final inviterEmail = (data['email'] ?? '').toString();
    final me = UserPaths.normalize(myEmail);
    if (inviterEmail == me) return 'You cannot use your own invite code.';
    if (inviterRole == myRole) {
      final need = myRole == 'Child' ? 'Guardian' : 'Child';
      return 'This code belongs to another $myRole. Ask a $need for their code.';
    }

    final childEmail = myRole == 'Child' ? me : inviterEmail;
    final guardianEmail = myRole == 'Guardian' ? me : inviterEmail;

    final childData = (await UserPaths.child(childEmail).get()).data() ?? {};
    final guardianData = (await UserPaths.guardian(guardianEmail).get()).data() ?? {};
    final hasPrimary = (await UserPaths.child(childEmail)
            .collection('emergency_contacts')
            .where('isPrimary', isEqualTo: true)
            .limit(1)
            .get())
        .docs
        .isNotEmpty;

    final childName = (childData['name'] ?? childEmail).toString();
    final guardianName = (guardianData['name'] ?? guardianEmail).toString();

    await FirestoreContactService().linkGuardianAndChildContacts(
      childEmail: childEmail,
      guardianEmail: guardianEmail,
      relationship: 'Guardian',
      childName: childName,
      guardianName: guardianName,
      guardianMobile: (guardianData['mobile'] ?? '').toString(),
      guardianUid: (guardianData['uid'] ?? '').toString(),
      childMobile: (childData['mobile'] ?? '').toString(),
      childUid: (childData['uid'] ?? '').toString(),
      isPrimary: !hasPrimary,
    );
    await UserPaths.guardian(guardianEmail).collection('children').doc(childEmail).set({
      'name': childName,
      'email': childEmail,
      'relationship': 'Guardian',
      'addedAt': FieldValue.serverTimestamp(),
      'via': 'invite',
    }, SetOptions(merge: true));
    await UserPaths.notifyGuardian(
      guardianEmail: guardianEmail,
      childEmail: childEmail,
      type: 'link_accepted',
      title: '$childName is now linked with you',
      body: 'Linked using invite code $code.',
    );
    return null;
  }
}
