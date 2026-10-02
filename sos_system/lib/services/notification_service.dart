import 'dart:typed_data';

import 'package:flutter/material.dart' show MaterialPageRoute;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sos_system/core/app_navigator.dart';
import 'package:sos_system/modules/guardian/views/guardian_alerts_page.dart';

/// Local (on-device) notifications for journey alerts, SOS and check-ins.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;
  int _nextId = 1000;

  static const _alertsChannel = AndroidNotificationDetails(
    'tg_alerts',
    'Journey & safety alerts',
    channelDescription: 'Journey started/completed, SOS and check-in replies',
    importance: Importance.high,
    priority: Priority.high,
  );

  static final _urgentChannel = AndroidNotificationDetails(
    'tg_urgent',
    'Urgent alerts',
    channelDescription: 'SOS alerts and "Are you OK?" check-ins',
    importance: Importance.max,
    priority: Priority.max,
    enableVibration: true,
    vibrationPattern: Int64List.fromList([0, 800, 400, 800, 400, 800, 400, 1200]),
    category: AndroidNotificationCategory.alarm,
    ticker: 'TravelGuard alert',
  );

  Future<void> init() async {
    if (_ready) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (r) => _openFromPayload(r.payload),
    );
    _ready = true;
  }

  /// Payloads: "guardian_alerts:<email>" opens the Alerts page.
  /// "checkin" needs nothing: the check-in dialog is already on screen.
  void _openFromPayload(String? payload) {
    if (payload == null) return;
    if (payload.startsWith('guardian_alerts:')) {
      final email = payload.substring('guardian_alerts:'.length);
      appNavigatorKey.currentState?.push(MaterialPageRoute(
        builder: (_) => GuardianAlertsPage(guardianEmail: email),
      ));
    }
  }

  Future<void> requestPermission() async {
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
  }

  Future<void> show(String title, String body,
      {bool urgent = false, String? payload}) async {
    await init();
    await _plugin.show(
      _nextId++,
      title,
      body,
      NotificationDetails(android: urgent ? _urgentChannel : _alertsChannel),
      payload: payload,
    );
  }
}
