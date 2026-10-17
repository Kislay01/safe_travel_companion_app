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
  LatLngLite? _lastSent;
  DateTime _lastSentAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _busy = false;

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
    if (email == null || _busy) return;
    _busy = true;
    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } catch (e) {
      // No fresh fix (indoors, underground, slow GPS): use a recent last-known
      // position if there is one.
      log('Location fix failed: $e');
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null && DateTime.now().difference(last.timestamp).inMinutes < 2) pos = last;
      } catch (_) {}
    } finally {
      // Only the GPS read is guarded: database writes below never block the
      // next tick (Firestore queues them locally when the network is slow).
      _busy = false;
    }

    if (pos == null) {
      // Still send a heartbeat so guardians know the phone is alive.
      if (force || DateTime.now().difference(_lastSentAt) >= _maxSilence) {
        _write(email, {'timestamp': DateTime.now().millisecondsSinceEpoch, 'gpsOk': false});
      }
      return;
    }
    reportPosition(pos.latitude, pos.longitude, force: force);
  }

  /// Uploads a position (from the background timer or the Journey screen's
  /// live stream) when the traveller has moved, or at least once a minute.
  void reportPosition(double lat, double lng, {bool force = false}) {
    // Arrival and re-routing work even when the Journey screen is not open.
    JourneyService.instance
        .onPosition(lat, lng)
        .catchError((e) => log('Journey update failed: $e'));

    final email = _childEmail;
    if (email == null) return;

    final last = _lastSent;
    final moved = last == null
        ? double.infinity
        : Geolocator.distanceBetween(last.latitude, last.longitude, lat, lng);
    final silentFor = DateTime.now().difference(_lastSentAt);
    if (!force && moved < _minMoveMeters && silentFor < _maxSilence) return;

    _write(email, {
      'latitude': lat,
      'longitude': lng,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'gpsOk': true,
    });
    _lastSent = LatLngLite(lat, lng);
    _lastSentAt = DateTime.now();
  }

  void _write(String email, Map<String, dynamic> data) {
    UserPaths.child(email)
        .collection('live_location')
        .doc('current')
        .set(data, SetOptions(merge: true))
        .catchError((e) => log('Location write failed: $e'));
    if (data.containsKey('timestamp')) _lastSentAt = DateTime.now();
  }
}

/// Minimal lat/lng pair for the "has the traveller moved?" check.
class LatLngLite {
  final double latitude;
  final double longitude;
  const LatLngLite(this.latitude, this.longitude);
}
