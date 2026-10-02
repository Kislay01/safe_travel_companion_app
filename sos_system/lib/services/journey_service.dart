import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:sos_system/core/user_paths.dart';
import 'package:sos_system/services/routes_service.dart';

class ActiveJourney {
  final String id;
  final String fromName;
  final String toName;
  final LatLng destination;
  const ActiveJourney(this.id, this.fromName, this.toName, this.destination);
}

/// Child-side journey lifecycle: start → (arrive | end) with guardian alerts.
///
/// Firestore:
///   Child/{email}/journeys/{id}  {from, to, fromLat.., status, startedAt, endedAt, polyline}
///   Child/{email}.activeJourneyId
class JourneyService {
  JourneyService._();
  static final JourneyService instance = JourneyService._();

  /// Distance (m) from the destination that counts as "arrived".
  static const double arrivalRadiusMeters = 75;

  String? _childEmail;
  String _childName = '';
  final ValueNotifier<ActiveJourney?> active = ValueNotifier(null);
  bool _finishing = false;

  /// Called when a child session starts; restores a journey left active.
  Future<void> attach({required String childEmail, required String childName}) async {
    _childEmail = UserPaths.normalize(childEmail);
    _childName = childName;
    try {
      final childSnap = await UserPaths.child(_childEmail!).get();
      final id = childSnap.data()?['activeJourneyId'] as String?;
      if (id == null || id.isEmpty) {
        active.value = null;
        return;
      }
      final j = await UserPaths.child(_childEmail!).collection('journeys').doc(id).get();
      final d = j.data();
      if (d == null || d['status'] != 'active') {
        active.value = null;
        return;
      }
      active.value = ActiveJourney(
        id,
        (d['from'] ?? '').toString(),
        (d['to'] ?? '').toString(),
        LatLng((d['toLat'] as num).toDouble(), (d['toLng'] as num).toDouble()),
      );
    } catch (e) {
      debugPrint('JourneyService.attach: $e');
    }
  }

  void detach() {
    _childEmail = null;
    active.value = null;
  }

  String get _displayName => _childName.isNotEmpty ? _childName : (_childEmail ?? 'Your child');

  Future<void> start({
    required String fromName,
    required String toName,
    required LatLng from,
    required LatLng to,
    required RouteResult route,
  }) async {
    final email = _childEmail;
    if (email == null) return;
    if (active.value != null) await finish(arrived: false);

    final ref = UserPaths.child(email).collection('journeys').doc();
    await ref.set({
      'from': fromName,
      'to': toName,
      'fromLat': from.latitude,
      'fromLng': from.longitude,
      'toLat': to.latitude,
      'toLng': to.longitude,
      'polyline': route.encodedPolyline,
      'distanceMeters': route.distanceMeters,
      'durationSeconds': route.durationSeconds,
      'status': 'active',
      'startedAt': FieldValue.serverTimestamp(),
    });
    await UserPaths.child(email).set({'activeJourneyId': ref.id}, SetOptions(merge: true));
    active.value = ActiveJourney(ref.id, fromName, toName, to);

    final mins = (route.durationSeconds / 60).round();
    final km = (route.distanceMeters / 1000).toStringAsFixed(1);
    await UserPaths.notifyGuardians(
      childEmail: email,
      type: 'journey_started',
      title: '$_displayName started a journey',
      body: 'From $fromName to $toName · $km km, about $mins min',
      extra: {'journeyId': ref.id},
    );
  }

  /// Call on every location update; completes the journey near the destination.
  Future<void> checkArrival(double lat, double lng) async {
    final j = active.value;
    if (j == null || _finishing) return;
    final d = Geolocator.distanceBetween(
        lat, lng, j.destination.latitude, j.destination.longitude);
    if (d <= arrivalRadiusMeters) await finish(arrived: true);
  }

  Future<void> finish({required bool arrived}) async {
    final email = _childEmail;
    final j = active.value;
    if (email == null || j == null || _finishing) return;
    _finishing = true;
    try {
      active.value = null;
      await UserPaths.child(email).collection('journeys').doc(j.id).update({
        'status': arrived ? 'completed' : 'ended',
        'endedAt': FieldValue.serverTimestamp(),
      });
      await UserPaths.child(email).set({'activeJourneyId': null}, SetOptions(merge: true));
      await UserPaths.notifyGuardians(
        childEmail: email,
        type: arrived ? 'journey_completed' : 'journey_ended',
        title: arrived
            ? '$_displayName reached ${j.toName}'
            : '$_displayName ended the journey early',
        body: arrived
            ? 'Journey from ${j.fromName} completed safely.'
            : 'Journey to ${j.toName} was stopped before arriving.',
        extra: {'journeyId': j.id},
      );
    } catch (e) {
      debugPrint('JourneyService.finish: $e');
    } finally {
      _finishing = false;
    }
  }
}
