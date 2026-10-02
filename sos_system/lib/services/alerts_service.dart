import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sos_system/common/views/safety_dialogs.dart';
import 'package:sos_system/core/app_navigator.dart';
import 'package:sos_system/core/user_paths.dart';
import 'package:sos_system/services/checkin_service.dart';
import 'package:sos_system/services/notification_service.dart';
import 'package:sos_system/services/sos_service.dart';

/// Listens to Firestore while the app process is alive and turns new
/// alerts into phone notifications (guardian) or check-in prompts (child).
class AlertsService {
  AlertsService._();
  static final AlertsService instance = AlertsService._();

  StreamSubscription? _sub;
  final Set<String> _seen = {};
  final Set<String> _openCheckins = {};

  void stop() {
    _sub?.cancel();
    _sub = null;
    _seen.clear();
    _openCheckins.clear();
  }

  Future<void> startGuardian(String guardianEmail) async {
    stop();
    await NotificationService.instance.init();
    final since = Timestamp.fromDate(DateTime.now().subtract(const Duration(minutes: 1)));
    _sub = UserPaths.guardian(guardianEmail)
        .collection('notifications')
        .where('createdAt', isGreaterThan: since)
        .snapshots()
        .listen((snap) {
      for (final ch in snap.docChanges) {
        if (ch.type != DocumentChangeType.added || !_seen.add(ch.doc.id)) continue;
        final d = ch.doc.data();
        if (d == null) continue;
        final type = (d['type'] ?? '').toString();
        final urgent = type == 'sos' || (type == 'checkin_response' && d['status'] == 'help');
        NotificationService.instance.show(
          (d['title'] ?? 'TravelGuard').toString(),
          (d['body'] ?? '').toString(),
          urgent: urgent,
          payload: 'guardian_alerts:${UserPaths.normalize(guardianEmail)}',
        );
      }
    }, onError: (e) => debugPrint('Guardian alerts listener: $e'));
  }

  Future<void> startChild({required String childEmail, required String childName}) async {
    stop();
    await NotificationService.instance.init();
    _sub = UserPaths.child(childEmail)
        .collection('checkins')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snap) {
      for (final ch in snap.docChanges) {
        if (ch.type != DocumentChangeType.added) continue;
        final d = ch.doc.data();
        if (d == null) continue;
        final created = (d['createdAt'] as Timestamp?)?.toDate();
        if (created != null && DateTime.now().difference(created).inMinutes >= 10) continue;
        _handleCheckin(ch.doc.id, d, childEmail, childName);
      }
    }, onError: (e) => debugPrint('Child check-in listener: $e'));
  }

  Future<void> _handleCheckin(
      String id, Map<String, dynamic> d, String childEmail, String childName) async {
    if (!_openCheckins.add(id)) return;
    final guardianEmail = (d['guardianEmail'] ?? '').toString();
    final guardianName = (d['guardianName'] ?? '').toString().isNotEmpty
        ? d['guardianName'].toString()
        : guardianEmail;

    await NotificationService.instance.show(
      'Are you OK?',
      '$guardianName is checking on you. Open TravelGuard to reply.',
      urgent: true,
      payload: 'checkin',
    );

    final ctx = appContext;
    if (ctx == null) return;
    final ok = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => CheckinDialog(guardianName: guardianName),
    );
    _openCheckins.remove(id);
    if (ok == null) return;

    try {
      await CheckinService.respond(
        childEmail: childEmail,
        childName: childName,
        checkinId: id,
        guardianEmail: guardianEmail,
        ok: ok,
      );
    } catch (e) {
      debugPrint('Check-in reply failed: $e');
    }
    if (!ok) {
      final msg = await SosService.trigger(source: 'checkin');
      final c = appContext;
      if (c != null && c.mounted) {
        ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }
}
