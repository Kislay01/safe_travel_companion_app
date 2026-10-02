import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, debugPrint;
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sos_system/core/user_paths.dart';
import 'package:sos_system/modules/auth/controllers/shared_preference_data.dart';
import 'package:url_launcher/url_launcher.dart';

/// One SOS pipeline for the button, voice trigger and "Need help" check-in reply:
/// 1) save alert with location  2) alert every guardian  3) call primary contact.
class SosService {
  SosService._();

  static bool _running = false;

  /// Returns a short status message for the UI.
  static Future<String> trigger({required String source}) async {
    if (_running) return 'SOS already in progress';
    _running = true;
    try {
      final prefs = SharedPreferenceData();
      await prefs.getSharedPreferenceData();
      final email = UserPaths.normalize(
          prefs.email.isNotEmpty ? prefs.email : (FirebaseAuth.instance.currentUser?.email ?? ''));
      if (email.isEmpty) return 'Please log in again.';
      final name = prefs.name.isNotEmpty ? prefs.name : email;

      final pos = await _position();
      final mapLink = pos == null
          ? 'Location unavailable'
          : 'https://maps.google.com/?q=${pos.latitude},${pos.longitude}';

      try {
        await UserPaths.child(email).collection('sos_alerts').add({
          'source': source,
          'latitude': pos?.latitude,
          'longitude': pos?.longitude,
          'createdAt': FieldValue.serverTimestamp(),
        });
        await UserPaths.notifyGuardians(
          childEmail: email,
          type: 'sos',
          title: '🆘 SOS from $name',
          body: '$name needs help. $mapLink',
          extra: {'latitude': pos?.latitude, 'longitude': pos?.longitude, 'source': source},
        );
      } catch (e) {
        debugPrint('SOS alert write failed: $e');
      }

      return await _callPrimary(email);
    } finally {
      _running = false;
    }
  }

  static Future<Position?> _position() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return await Geolocator.getLastKnownPosition();
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (_) {
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (_) {
        return null;
      }
    }
  }

  static Future<String> _callPrimary(String email) async {
    final contacts = UserPaths.child(email).collection('emergency_contacts');
    var q = await contacts.where('isPrimary', isEqualTo: true).limit(1).get();
    if (q.docs.isEmpty) q = await contacts.limit(1).get();
    final phone = q.docs.isEmpty ? '' : (q.docs.first.data()['mobile'] ?? '').toString().trim();
    if (phone.isEmpty) return 'Guardians alerted. No phone number saved for your primary contact.';

    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final status = await Permission.phone.request();
        if (status.isGranted) {
          final ok = await FlutterPhoneDirectCaller.callNumber(phone);
          if (ok == true) return 'Guardians alerted. Calling primary contact…';
        }
      }
      final uri = Uri(scheme: 'tel', path: phone);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return 'Guardians alerted. Opening dialer…';
      }
      return 'Guardians alerted. Could not start the call.';
    } catch (e) {
      return 'Guardians alerted. Call failed: $e';
    }
  }
}
