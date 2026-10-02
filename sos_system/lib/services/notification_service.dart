import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

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
    await _plugin.initialize(settings);
    _ready = true;
  }

  Future<void> requestPermission() async {
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
  }

  Future<void> show(String title, String body, {bool urgent = false}) async {
    await init();
    await _plugin.show(
      _nextId++,
      title,
      body,
      NotificationDetails(android: urgent ? _urgentChannel : _alertsChannel),
    );
  }
}
