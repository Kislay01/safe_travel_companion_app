import 'dart:async';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sos_system/core/user_paths.dart';
import 'package:sos_system/services/journey_service.dart';

/// Keeps the app alive in the background (foreground service) and, for a
/// child, shares live location to Child/{email}/live_location/current.
class LocationSharingService {
  LocationSharingService._();
  static final LocationSharingService instance = LocationSharingService._();

  static const _tick = Duration(seconds: 15);
  static const _minMoveMeters = 10.0;
  static const _maxSilence = Duration(seconds: 60);

  Timer? _timer;
  String? _childEmail;
  Position? _lastSent;
  DateTime _lastSentAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get isSharing => _timer != null;

  /// Keeps the process alive so Firestore listeners (alerts, check-ins) keep working.
  Future<void> enableBackground({required String title, required String text}) async {
    try {
      final config = FlutterBackgroundAndroidConfig(
        notificationTitle: title,
        notificationText: text,
        notificationImportance: AndroidNotificationImportance.normal,
        enableWifiLock: true,
      );
      final ok = await FlutterBackground.initialize(androidConfig: config);
      if (ok && !FlutterBackground.isBackgroundExecutionEnabled) {
        await FlutterBackground.enableBackgroundExecution();
      }
    } catch (e) {
      log('Background execution unavailable: $e');
    }
  }

  Future<void> startSharing(String childEmail) async {
    stopSharing(keepBackground: true);
    _childEmail = UserPaths.normalize(childEmail);
    if (!await _ensurePermissions()) return;

    await enableBackground(
      title: 'TravelGuard is protecting you',
      text: 'Sharing your live location with your guardians',
    );
    await _update(force: true);
    _timer = Timer.periodic(_tick, (_) => _update());
    log('Location sharing started for $_childEmail');
  }

  void stopSharing({bool keepBackground = false}) {
    _timer?.cancel();
    _timer = null;
    _lastSent = null;
    if (!keepBackground) disableBackground();
  }

  Future<void> disableBackground() async {
    try {
      if (FlutterBackground.isBackgroundExecutionEnabled) {
        await FlutterBackground.disableBackgroundExecution();
      }
    } catch (_) {}
  }

  Future<bool> _ensurePermissions() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      log('Location services are disabled.');
      return false;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  Future<void> _update({bool force = false}) async {
    final email = _childEmail;
    if (email == null) return;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      // Arrival detection works even when the Journey screen is not open.
      await JourneyService.instance.checkArrival(pos.latitude, pos.longitude);

      final moved = _lastSent == null
          ? double.infinity
          : Geolocator.distanceBetween(_lastSent!.latitude, _lastSent!.longitude,
              pos.latitude, pos.longitude);
      final silentFor = DateTime.now().difference(_lastSentAt);
      if (!force && moved < _minMoveMeters && silentFor < _maxSilence) return;

      await UserPaths.child(email).collection('live_location').doc('current').set({
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      }, SetOptions(merge: true));
      _lastSent = pos;
      _lastSentAt = DateTime.now();
    } catch (e) {
      log('Location update failed: $e');
    }
  }
}
