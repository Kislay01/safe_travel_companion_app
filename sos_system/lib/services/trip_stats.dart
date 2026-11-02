import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sos_system/core/user_paths.dart';

/// One journey reduced to what the stats need.
class TripRecord {
  final String status; // active | completed | ended
  final DateTime? startedAt;
  final int distanceMeters;
  const TripRecord(this.status, this.startedAt, this.distanceMeters);
}

/// Last-30-days summary shown on Home (child) and in a child's card (guardian).
class TripStats {
  final int trips; // journeys started in the window
  final double km; // planned distance of finished journeys in the window
  final int arrived; // reached the destination
  final int streak; // safe arrivals in a row, most recent first
  final int sos; // SOS alerts in the window

  const TripStats({this.trips = 0, this.km = 0, this.arrived = 0, this.streak = 0, this.sos = 0});

  static const windowDays = 30;

  /// Pure: [records] newest first. Active journeys are skipped for the streak.
  static TripStats compute(List<TripRecord> records, {required DateTime now, int sos = 0}) {
    final since = now.subtract(const Duration(days: windowDays));
    var trips = 0, arrived = 0, meters = 0;
    for (final r in records) {
      final t = r.startedAt;
      if (t == null || t.isBefore(since)) continue;
      trips++;
      if (r.status == 'completed') arrived++;
      if (r.status != 'active') meters += r.distanceMeters;
    }
    var streak = 0;
    for (final r in records) {
      if (r.status == 'active') continue;
      if (r.status != 'completed') break;
      streak++;
    }
    return TripStats(trips: trips, km: meters / 1000.0, arrived: arrived, streak: streak, sos: sos);
  }

  /// Reads the child's last 50 journeys and this month's SOS count.
  static Future<TripStats> load(String childEmail, {DateTime? now}) async {
    final n = now ?? DateTime.now();
    final child = UserPaths.child(childEmail);
    final snap = await child.collection('journeys').orderBy('startedAt', descending: true).limit(50).get();
    final records = snap.docs.map((d) {
      final m = d.data();
      final at = m['startedAt'];
      return TripRecord(
        (m['status'] ?? '').toString(),
        at is Timestamp ? at.toDate() : null,
        (m['distanceMeters'] is num) ? (m['distanceMeters'] as num).toInt() : 0,
      );
    }).toList();
    var sos = 0;
    try {
      final since = Timestamp.fromDate(n.subtract(const Duration(days: windowDays)));
      final agg = await child.collection('sos_alerts').where('createdAt', isGreaterThanOrEqualTo: since).count().get();
      sos = agg.count ?? 0;
    } catch (_) {}
    return compute(records, now: n, sos: sos);
  }
}
