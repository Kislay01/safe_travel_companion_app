import 'package:flutter_test/flutter_test.dart';
import 'package:sos_system/services/profile_service.dart';
import 'package:sos_system/services/trip_stats.dart';

void main() {
  final now = DateTime(2026, 11, 2, 20);
  DateTime ago(int d) => now.subtract(Duration(days: d));

  group('TripStats.compute', () {
    test('counts trips, km and arrivals in the last 30 days', () {
      final s = TripStats.compute([
        TripRecord('active', ago(0), 4000),
        TripRecord('completed', ago(1), 5200),
        TripRecord('ended', ago(3), 1800),
        TripRecord('completed', ago(10), 3000),
        TripRecord('completed', ago(45), 9999), // outside the window
      ], now: now, sos: 1);
      expect(s.trips, 4);
      expect(s.arrived, 2);
      expect(s.km, closeTo(10.0, 1e-9)); // active trip not counted
      expect(s.sos, 1);
    });

    test('streak: consecutive arrivals, skipping the active trip, stops at an early end', () {
      final s = TripStats.compute([
        TripRecord('active', ago(0), 0),
        TripRecord('completed', ago(1), 0),
        TripRecord('completed', ago(2), 0),
        TripRecord('completed', ago(40), 0), // older than 30 days still counts
        TripRecord('ended', ago(41), 0),
        TripRecord('completed', ago(42), 0),
      ], now: now);
      expect(s.streak, 3);
    });

    test('no journeys', () {
      final s = TripStats.compute(const [], now: now);
      expect(s.trips, 0);
      expect(s.km, 0);
      expect(s.streak, 0);
    });

    test('missing start time is ignored for the window', () {
      final s = TripStats.compute([const TripRecord('completed', null, 1000)], now: now);
      expect(s.trips, 0);
      expect(s.streak, 1);
    });
  });

  group('MedicalInfo', () {
    test('summary lists only filled fields', () {
      const m = MedicalInfo(bloodGroup: 'B+', allergies: 'penicillin', conditions: 'Asthma');
      expect(m.summary, 'Blood B+ · Allergies: penicillin · Asthma');
      expect(m.isEmpty, isFalse);
    });

    test('round trip and empty', () {
      const m = MedicalInfo(bloodGroup: 'O-', medications: 'inhaler', notes: 'in my bag');
      final back = MedicalInfo.fromMap(m.toMap());
      expect(back.summary, m.summary);
      expect(MedicalInfo.fromMap(null).isEmpty, isTrue);
      expect(MedicalInfo.fromMap({'bloodGroup': '  '}).isEmpty, isTrue);
    });
  });
}
