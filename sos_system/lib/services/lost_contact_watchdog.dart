import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:sos_system/core/user_paths.dart';

/// Guardian side: raises an alert when a traveller on an active journey stops
/// sending location updates (phone switched off, broken, battery dead or out
/// of network). It runs entirely on the guardian's phone, so it still works
/// when the traveller's phone can do nothing at all.
///
/// The traveller's phone writes Child/{email}/live_location/current at least
/// every ~75 s while sharing, so a few minutes of silence during a journey is
/// a strong signal that something is wrong.
class LostContactWatchdog {
  LostContactWatchdog._();
  static final LostContactWatchdog instance = LostContactWatchdog._();

  /// How long a journey may go without a location update before we alert.
  static const Duration silenceLimit = Duration(minutes: 3);
  static const Duration _checkEvery = Duration(seconds: 20);

  /// On first read, a traveller timestamp older than this is treated as real
  /// silence rather than a clock difference between the two phones.
  static const Duration _staleOnOpen = Duration(minutes: 10);

  String? _guardianEmail;
  final Map<String, _WatchedTraveller> _travellers = {};
  Timer? _timer;
  StreamSubscription? _contactsSub;

  bool get isRunning => _timer != null;

  Future<void> start(String guardianEmail) async {
    stop();
    _guardianEmail = UserPaths.normalize(guardianEmail);
    // Follow the guardian's linked travellers, including ones linked later.
    _contactsSub = UserPaths.guardian(_guardianEmail!)
        .collection('emergency_contacts')
        .snapshots()
        .listen((snap) {
      final current = <String>{};
      for (final doc in snap.docs) {
        final d = doc.data();
        if ((d['role'] ?? 'Child') != 'Child') continue;
        final email = UserPaths.normalize(doc.id);
        current.add(email);
        if (_travellers.containsKey(email)) continue;
        final name = (d['name'] ?? '').toString();
        _watch(email, name.isNotEmpty ? name : email);
      }
      // Stop watching travellers who were unlinked.
      for (final email in _travellers.keys.toList()) {
        if (!current.contains(email)) _travellers.remove(email)?.cancel();
      }
    }, onError: (e) => debugPrint('Watchdog contacts listener: $e'));
    _timer = Timer.periodic(_checkEvery, (_) => _check());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _contactsSub?.cancel();
    _contactsSub = null;
    for (final t in _travellers.values) {
      t.cancel();
    }
    _travellers.clear();
    _guardianEmail = null;
  }

  void _watch(String email, String name) {
    final t = _WatchedTraveller(email, name);
    _travellers[email] = t;

    // Journey state: only watch while a journey is active.
    t.journeySub = UserPaths.child(email).snapshots().listen((snap) {
      final id = snap.data()?['activeJourneyId'] as String?;
      final newId = (id == null || id.isEmpty) ? null : id;
      final firstRead = !t.journeyRead;
      t.journeyRead = true;
      if (newId == t.journeyId) return;
      t.journeyId = newId;
      t.alerted = false;
      t.destination = '';
      if (newId != null) {
        // A journey that starts while we're watching gets a full silence
        // window. One already running when this app opened is judged by the
        // traveller's last update instead (set by the location listener).
        if (!firstRead || t.lastSeen == null) t.lastSeen = DateTime.now();
        _loadDestination(t, newId);
      }
    }, onError: (e) => debugPrint('Watchdog journey listener ($email): $e'));

    // Heartbeat: every upload from the traveller's phone carries a new
    // 'timestamp'. Only a changed timestamp counts, so cache reads and
    // reconnects of this phone are never mistaken for the traveller.
    t.locationSub = UserPaths.child(email)
        .collection('live_location')
        .doc('current')
        .snapshots()
        .listen((snap) {
      final d = snap.data();
      if (d == null) return;
      final ts = d['timestamp'];
      if (ts is! num) return;
      final tsInt = ts.toInt();
      if (tsInt == t.lastTimestamp) return;

      final lat = d['latitude'];
      final lng = d['longitude'];
      if (lat is num && lng is num) {
        t.lastLat = lat.toDouble();
        t.lastLng = lng.toDouble();
      }

      final now = DateTime.now();
      final firstRead = t.lastTimestamp == null;
      t.lastTimestamp = tsInt;
      if (firstRead) {
        // First read: the traveller's timestamp comes from another phone's
        // clock, so only trust it when it is clearly stale (a phone that was
        // already silent before this app opened). Otherwise start fresh, so a
        // small clock difference can't raise a false alarm.
        final sent = DateTime.fromMillisecondsSinceEpoch(tsInt);
        t.lastSeen = now.difference(sent) > _staleOnOpen ? sent : now;
        return;
      }

      // Later updates: use the time we received them, so clock differences
      // between the two phones can't cause false alarms.
      t.lastSeen = now;
      if (t.alerted) {
        t.alerted = false;
        _notify(
          t,
          type: 'contact_restored',
          title: 'Back in contact with ${t.name}',
          body: 'Updates from their phone have resumed${_toText(t)}.',
        );
      }
    }, onError: (e) => debugPrint('Watchdog location listener ($email): $e'));
  }

  Future<void> _loadDestination(_WatchedTraveller t, String journeyId) async {
    try {
      final j = await UserPaths.child(t.email).collection('journeys').doc(journeyId).get();
      if (t.journeyId == journeyId) t.destination = (j.data()?['to'] ?? '').toString();
    } catch (e) {
      debugPrint('Watchdog destination ($journeyId): $e');
    }
  }

  void _check() {
    final now = DateTime.now();
    for (final t in _travellers.values) {
      final seen = t.lastSeen;
      if (t.journeyId == null || t.alerted || seen == null) continue;
      final silent = now.difference(seen);
      if (silent < silenceLimit) continue;

      t.alerted = true;
      final mins = silent.inMinutes;
      _notify(
        t,
        type: 'lost_contact',
        title: 'Lost contact with ${t.name}',
        body: 'No update from their phone for $mins min${_toText(t)}. '
            'Last seen at ${DateFormat('hh:mm a').format(seen)}. Try calling them now.',
      );
    }
  }

  String _toText(_WatchedTraveller t) =>
      t.destination.isNotEmpty ? ' during the journey to ${t.destination}' : '';

  Future<void> _notify(
    _WatchedTraveller t, {
    required String type,
    required String title,
    required String body,
  }) async {
    final g = _guardianEmail;
    if (g == null) return;
    try {
      await UserPaths.notifyGuardian(
        guardianEmail: g,
        childEmail: t.email,
        type: type,
        title: title,
        body: body,
        extra: {
          // Local time so this phone's own alert listener picks it up at once.
          'createdAt': Timestamp.now(),
          if (t.journeyId != null) 'journeyId': t.journeyId,
          if (t.lastLat != null && t.lastLng != null) ...{
            'latitude': t.lastLat,
            'longitude': t.lastLng,
          },
        },
      );
    } catch (e) {
      debugPrint('Watchdog notify failed: $e');
    }
  }
}

class _WatchedTraveller {
  _WatchedTraveller(this.email, this.name);

  final String email;
  final String name;
  String? journeyId;
  String destination = '';
  DateTime? lastSeen;
  double? lastLat;
  double? lastLng;
  int? lastTimestamp;
  bool journeyRead = false;
  bool alerted = false;
  StreamSubscription? journeySub;
  StreamSubscription? locationSub;

  void cancel() {
    journeySub?.cancel();
    locationSub?.cancel();
  }
}
