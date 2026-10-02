import 'package:flutter/foundation.dart';
import 'package:sos_system/services/alerts_service.dart';
import 'package:sos_system/services/journey_service.dart';
import 'package:sos_system/services/location_sharing_service.dart';
import 'package:sos_system/services/notification_service.dart';
import 'package:sos_system/services/voice_sos_service.dart';

/// Starts/stops everything that runs for a logged-in user.
class SessionServices {
  SessionServices._();

  static Future<void> start({
    required String role,
    required String email,
    required String name,
  }) async {
    // Each step is guarded separately so one failure (e.g. a denied
    // permission) can't stop the others from starting.
    await _step('notifications', () async {
      await NotificationService.instance.init();
      await NotificationService.instance.requestPermission();
    });

    if (role == 'Child') {
      // Check-in listener first: it must not wait behind permission prompts.
      await _step('alerts', () => AlertsService.instance.startChild(childEmail: email, childName: name));
      await _step('journey', () => JourneyService.instance.attach(childEmail: email, childName: name));
      await _step('location', () => LocationSharingService.instance.startSharing(email));
      await _step('voice', () async {
        if (await VoiceSosService.isEnabledInPrefs()) await VoiceSosService.instance.start();
      });
    } else {
      await _step('alerts', () => AlertsService.instance.startGuardian(email));
      await _step('background', () => LocationSharingService.instance.enableBackground(
            title: 'TravelGuard guardian mode',
            text: 'Watching for alerts from your children',
          ));
    }
  }

  static Future<void> _step(String name, Future<void> Function() run) async {
    try {
      await run();
    } catch (e) {
      debugPrint('SessionServices.$name: $e');
    }
  }

  static Future<void> stop() async {
    await VoiceSosService.instance.stop();
    AlertsService.instance.stop();
    LocationSharingService.instance.stopSharing();
    JourneyService.instance.detach();
  }
}
