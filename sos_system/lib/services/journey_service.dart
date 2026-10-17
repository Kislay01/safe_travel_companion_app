import 'dart:math';

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

  /// Distance (m) from the planned route that counts as "off route".
  static const double offRouteMeters = 120;

  /// Minimum gap between two automatic re-routes (keeps Routes API use low).
  static const Duration rerouteCooldown = Duration(seconds: 60);

  String? _childEmail;
  String _childName = '';
  final ValueNotifier<ActiveJourney?> active = ValueNotifier(null);

  /// The route currently being followed; replaced when the traveller re-routes.
  final ValueNotifier<RouteResult?> route = ValueNotifier(null);

  bool _finishing = false;
  bool _rerouting = false;
  int _offRouteCount = 0;
  DateTime _lastReroute = DateTime.fromMillisecondsSinceEpoch(0);

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
      final encoded = (d['polyline'] ?? '').toString();
      route.value = RouteResult(
        encodedPolyline: encoded,
        points: RoutesService.decodePolyline(encoded),
        steps: const [],
        distanceMeters: (d['distanceMeters'] as num?)?.toInt() ?? 0,
        durationSeconds: (d['durationSeconds'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      debugPrint('JourneyService.attach: $e');
    }
  }

  void detach() {
    _childEmail = null;
    active.value = null;
    route.value = null;
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
    this.route.value = route;
    _offRouteCount = 0;
    _lastReroute = DateTime.now();

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

  /// Call on every location update: completes the journey near the
  /// destination, and re-routes (like Google Maps) when the traveller leaves
  /// the planned route.
  Future<void> onPosition(double lat, double lng) async {
    await checkArrival(lat, lng);
    final j = active.value;
    final r = route.value;
    if (j == null || r == null || r.points.length < 2 || _rerouting || _finishing) return;

    final off = _distanceToRoute(LatLng(lat, lng), r.points) > offRouteMeters;
    _offRouteCount = off ? _offRouteCount + 1 : 0;
    // Two off-route readings in a row, so one GPS jump can't trigger it.
    if (_offRouteCount < 2) return;
    if (DateTime.now().difference(_lastReroute) < rerouteCooldown) return;
    await _reroute(LatLng(lat, lng), j);
  }

  Future<void> _reroute(LatLng from, ActiveJourney j) async {
    final email = _childEmail;
    if (email == null) return;
    _rerouting = true;
    _lastReroute = DateTime.now();
    try {
      final newRoute = await RoutesService.computeRoute(origin: from, destination: j.destination);
      if (active.value?.id != j.id) return; // journey ended meanwhile
      route.value = newRoute;
      _offRouteCount = 0;

      await UserPaths.child(email).collection('journeys').doc(j.id).update({
        'polyline': newRoute.encodedPolyline,
        'distanceMeters': newRoute.distanceMeters,
        'durationSeconds': newRoute.durationSeconds,
        'rerouteCount': FieldValue.increment(1),
        'reroutedAt': FieldValue.serverTimestamp(),
      });
      // Touch the traveller doc so guardians' maps redraw the new route.
      await UserPaths.child(email).set(
          {'routeUpdatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));

      final mins = (newRoute.durationSeconds / 60).round();
      await UserPaths.notifyGuardians(
        childEmail: email,
        type: 'route_changed',
        title: '$_displayName took a different route',
        body: 'New route to ${j.toName} shown on the map \u00b7 about $mins min left',
        extra: {'journeyId': j.id, 'latitude': from.latitude, 'longitude': from.longitude},
      );
    } catch (e) {
      debugPrint('JourneyService.reroute: $e');
    } finally {
      _rerouting = false;
    }
  }

  /// Shortest distance (m) from [p] to the route line.
  static double _distanceToRoute(LatLng p, List<LatLng> pts) {
    var best = double.infinity;
    for (var i = 0; i < pts.length - 1; i++) {
      final d = _distanceToSegment(p, pts[i], pts[i + 1]);
      if (d < best) best = d;
    }
    return best;
  }

  static double _distanceToSegment(LatLng p, LatLng a, LatLng b) {
    // Flat-earth approximation in metres around [p]; accurate at city scale.
    const mPerDegLat = 111320.0;
    final mPerDegLng = 111320.0 * cos(p.latitude * pi / 180);
    final ax = (a.longitude - p.longitude) * mPerDegLng, ay = (a.latitude - p.latitude) * mPerDegLat;
    final bx = (b.longitude - p.longitude) * mPerDegLng, by = (b.latitude - p.latitude) * mPerDegLat;
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    var t = len2 == 0 ? 0.0 : -(ax * dx + ay * dy) / len2;
    t = t.clamp(0.0, 1.0).toDouble();
    final cx = ax + t * dx, cy = ay + t * dy;
    return sqrt(cx * cx + cy * cy);
  }

  /// Completes the journey near the destination.
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
      route.value = null;
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
