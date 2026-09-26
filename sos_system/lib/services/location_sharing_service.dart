import 'dart:async';
import 'dart:developer';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_background/flutter_background.dart';

class LocationSharingService {
  final String childEmail;
  Timer? _timer;

  LocationSharingService({required this.childEmail});

  /// Start continuous background location sharing
  Future<void> startSharing() async {
    log("🚀 Starting live location sharing for child: $childEmail");

    await _ensurePermissions();

    const androidConfig = FlutterBackgroundAndroidConfig(
      notificationTitle: "Live Location Active",
      notificationText: "Sharing your location securely with guardians",
      notificationImportance: AndroidNotificationImportance.normal,
      enableWifiLock: true,
    );

    bool backgroundEnabled = await FlutterBackground.initialize(androidConfig: androidConfig);
    if (backgroundEnabled) {
      await FlutterBackground.enableBackgroundExecution();
    }

    // Update every 10 seconds (adjust as needed)
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      await _updateLocation();
    });
  }

  /// Ensure location permissions and services are available
  Future<void> _ensurePermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      log("⚠️ Location services are disabled.");
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        log("❌ Location permission denied.");
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      log("❌ Location permission permanently denied.");
      return;
    }
  }

  /// Fetch current location and update both child + guardian collections
  Future<void> _updateLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final locationData = {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'timestamp': timestamp,
      };

      final firestore = FirebaseFirestore.instance;

      // 🔹 1. Update Child's own live location
      await firestore
          .collection('Child')
          .doc(childEmail)
          .collection('live_location')
          .doc('current')
          .set(locationData, SetOptions(merge: true));

      // 🔹 2. Get emergency contacts (guardians) for this child
      final childSnap = await firestore.collection('Child').doc(childEmail).get();
      final data = childSnap.data();
      if (data == null) {
        log("⚠️ No child data found for $childEmail");
        return;
      }

      final guardians = (data['emergencyContacts'] as List?)?.cast<String>() ?? [];

      // 🔹 3. Update each guardian's live child data
      for (final guardianEmail in guardians) {
        await firestore
            .collection('GuardianLive')
            .doc(guardianEmail)
            .collection('child_locations')
            .doc(childEmail)
            .set(locationData, SetOptions(merge: true));
      }

      log("✅ Updated live location for $childEmail to all guardians");
    } catch (e) {
      log("❌ Error updating location: $e");
    }
  }

  /// Stop background sharing
  void stopSharing() {
    _timer?.cancel();
    FlutterBackground.disableBackgroundExecution();
    log("🛑 Location sharing stopped for $childEmail");
  }
}
