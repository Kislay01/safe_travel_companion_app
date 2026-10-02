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
    try {
      await NotificationService.instance.init();
      await NotificationService.instance.requestPermission();

      if (role == 'Child') {
        await JourneyService.instance.attach(childEmail: email, childName: name);
        await LocationSharingService.instance.startSharing(email);
        await AlertsService.instance.startChild(childEmail: email, childName: name);
        if (await VoiceSosService.isEnabledInPrefs()) {
          await VoiceSosService.instance.start();
        }
      } else {
        await LocationSharingService.instance.enableBackground(
          title: 'TravelGuard guardian mode',
          text: 'Watching for alerts from your children',
        );
        await AlertsService.instance.startGuardian(email);
      }
    } catch (e) {
      debugPrint('SessionServices.start: $e');
    }
  }

  static Future<void> stop() async {
    await VoiceSosService.instance.stop();
    AlertsService.instance.stop();
    LocationSharingService.instance.stopSharing();
    JourneyService.instance.detach();
  }
}
