import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sos_system/core/user_paths.dart';

/// Health details a guardian (or a stranger helping) may need in an emergency.
/// Stored on the user's own doc as `medical`.
class MedicalInfo {
  final String bloodGroup;
  final String allergies;
  final String medications;
  final String conditions;
  final String notes;

  const MedicalInfo({
    this.bloodGroup = '',
    this.allergies = '',
    this.medications = '',
    this.conditions = '',
    this.notes = '',
  });

  static const bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

  factory MedicalInfo.fromMap(Map<String, dynamic>? m) {
    String s(String k) => (m?[k] ?? '').toString().trim();
    return MedicalInfo(
      bloodGroup: s('bloodGroup'),
      allergies: s('allergies'),
      medications: s('medications'),
      conditions: s('conditions'),
      notes: s('notes'),
    );
  }

  Map<String, dynamic> toMap() => {
        'bloodGroup': bloodGroup.trim(),
        'allergies': allergies.trim(),
        'medications': medications.trim(),
        'conditions': conditions.trim(),
        'notes': notes.trim(),
      };

  bool get isEmpty =>
      bloodGroup.isEmpty && allergies.isEmpty && medications.isEmpty && conditions.isEmpty && notes.isEmpty;

  /// One line for SOS alerts, e.g. "Blood B+ · Allergies: penicillin · Asthma".
  String get summary => [
        if (bloodGroup.isNotEmpty) 'Blood $bloodGroup',
        if (allergies.isNotEmpty) 'Allergies: $allergies',
        if (conditions.isNotEmpty) conditions,
        if (medications.isNotEmpty) 'Meds: $medications',
        if (notes.isNotEmpty) notes,
      ].join(' · ');
}

/// Profile photo and medical info, kept in the user's Firestore doc so the app
/// stays on the free plan (no Cloud Storage). Photos are resized to 256 px JPEG
/// (~15–30 KB), far under Firestore's 1 MB document limit.
class ProfileService {
  ProfileService._();

  static const int photoSize = 256;
  static const int maxPhotoBytes = 300 * 1024;

  static DocumentReference<Map<String, dynamic>> doc(String role, String email) =>
      role == 'Guardian' ? UserPaths.guardian(email) : UserPaths.child(email);

  /// Opens the gallery (or camera) and saves the picked photo. Returns false if cancelled.
  static Future<bool> pickAndSavePhoto({
    required String role,
    required String email,
    ImageSource source = ImageSource.gallery,
  }) async {
    final file = await ImagePicker().pickImage(
      source: source,
      maxWidth: photoSize.toDouble(),
      maxHeight: photoSize.toDouble(),
      imageQuality: 75,
      preferredCameraDevice: CameraDevice.front,
    );
    if (file == null) return false;
    final bytes = await file.readAsBytes();
    if (bytes.length > maxPhotoBytes) {
      throw StateError('That photo is too large. Try another one.');
    }
    await doc(role, email).set({
      'photo': base64Encode(bytes),
      'photoUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    _bytes.remove(UserPaths.normalize(email));
    return true;
  }

  static Future<void> removePhoto({required String role, required String email}) async {
    await doc(role, email).set({'photo': FieldValue.delete()}, SetOptions(merge: true));
    _bytes.remove(UserPaths.normalize(email));
  }

  static Future<MedicalInfo> loadMedical(String email) async {
    final d = await UserPaths.child(email).get();
    return MedicalInfo.fromMap((d.data()?['medical'] as Map?)?.cast<String, dynamic>());
  }

  static Future<void> saveMedical(String email, MedicalInfo info) =>
      UserPaths.child(email).set({'medical': info.toMap()}, SetOptions(merge: true));

  // ---- photo streams (shared + cached so lists and maps don't re-subscribe)

  static final Map<String, Stream<Uint8List?>> _streams = {};
  static final Map<String, Uint8List?> _bytes = {};

  /// Last known photo bytes (null = none or not loaded yet).
  static Uint8List? cached(String email) => _bytes[UserPaths.normalize(email)];

  static Stream<Uint8List?> photoOf(String role, String email) {
    final key = UserPaths.normalize(email);
    if (key.isEmpty) return Stream.value(null);
    return _streams.putIfAbsent(key, () {
      String? last;
      return doc(role, key)
          .snapshots()
          .map((s) {
            final b64 = s.data()?['photo'];
            if (b64 is! String || b64.isEmpty) {
              last = null;
              _bytes[key] = null;
              return null;
            }
            if (b64 == last && _bytes[key] != null) return _bytes[key];
            last = b64;
            try {
              final bytes = base64Decode(b64);
              _bytes[key] = bytes;
              return bytes;
            } catch (_) {
              return null;
            }
          })
          .handleError((_) {})
          .asBroadcastStream();
    });
  }
}
