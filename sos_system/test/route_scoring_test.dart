import 'package:flutter_test/flutter_test.dart';
import 'package:sos_system/services/route_scoring.dart';

RouteFacts facts(int dur, List<int?> counts, {int? staticDur, int dist = 5000}) => RouteFacts(
      durationSeconds: dur,
      staticDurationSeconds: staticDur ?? dur,
      distanceMeters: dist,
      placeCounts: counts,
    );

void main() {
  group('geometry', () {
    test('haversine: 0.01° latitude is about 1.11 km', () {
      final d = haversine(const GeoPt(18.5, 73.8), const GeoPt(18.51, 73.8));
      expect(d, closeTo(1112, 3));
    });

    test('samplePoints spreads points evenly and skips the ends', () {
      final line = [const GeoPt(18.5, 73.8), const GeoPt(18.6, 73.8)];
      final s = samplePoints(line, 5);
      expect(s.length, 5);
      expect(s.first.lat, closeTo(18.51, 1e-6));
      expect(s.last.lat, closeTo(18.59, 1e-6));
      expect(s[2].lat, closeTo(18.55, 1e-6));
    });

    test('samplePoints handles empty and single-point routes', () {
      expect(samplePoints(const [], 5), isEmpty);
      expect(samplePoints(const [GeoPt(1, 1)], 5).length, 1);
    });

    test('remainingMeters: halfway along a straight road', () {
      final line = [const GeoPt(18.5, 73.8), const GeoPt(18.52, 73.8)];
      final total = pathLength(line);
      final rem = remainingMeters(line, const GeoPt(18.51, 73.8005)); // ~50 m off the road
      expect(rem, closeTo(total / 2, 5));
    });

    test('remainingMeters: start and end of an L-shaped route', () {
      final line = [const GeoPt(18.5, 73.8), const GeoPt(18.51, 73.8), const GeoPt(18.51, 73.81)];
      expect(remainingMeters(line, line.first), closeTo(pathLength(line), 1));
      expect(remainingMeters(line, line.last), closeTo(0, 1));
    });
  });

  group('isNight', () {
    test('19:00 to 05:59 is night', () {
      expect(isNight(DateTime(2026, 1, 1, 19)), isTrue);
      expect(isNight(DateTime(2026, 1, 1, 2)), isTrue);
      expect(isNight(DateTime(2026, 1, 1, 6)), isFalse);
      expect(isNight(DateTime(2026, 1, 1, 18, 59)), isFalse);
    });
  });

  group('scoreRoutes', () {
    test('night: clearly busier route within the time budget is recommended', () {
      final s = scoreRoutes([facts(900, [2, 1, 2, 1, 2]), facts(1020, [8, 9, 7, 10, 8])], night: true);
      expect(s[0].fastest, isTrue);
      expect(s[1].busier, isTrue);
      expect(s[1].recommended, isTrue);
      expect(s[0].recommended, isFalse);
    });

    test('day: fastest is recommended even if another is busier', () {
      final s = scoreRoutes([facts(900, [2, 1, 2, 1, 2]), facts(1020, [8, 9, 7, 10, 8])], night: false);
      expect(s[1].busier, isTrue);
      expect(s[0].recommended, isTrue);
    });

    test('night: busier route that costs too much time is not recommended', () {
      // 1.5x the time
      final s = scoreRoutes([facts(900, [1, 1, 1, 1, 1]), facts(1350, [9, 9, 9, 9, 9])], night: true);
      expect(s[1].busier, isTrue);
      expect(s[0].recommended, isTrue);
      // within 25% but more than 10 minutes extra
      final t = scoreRoutes([facts(3000, [1, 1, 1, 1, 1]), facts(3700, [9, 9, 9, 9, 9])], night: true);
      expect(t[0].recommended, isTrue);
    });

    test('small differences never earn a "busier" badge', () {
      final s = scoreRoutes([facts(900, [10, 10, 10, 10, 10]), facts(960, [11, 11, 11, 11, 11])], night: true);
      expect(s.any((x) => x.busier), isFalse);
      expect(s[0].recommended, isTrue);
    });

    test('fastest route that is also busiest gets no separate busier badge', () {
      final s = scoreRoutes([facts(900, [9, 9, 9, 9, 9]), facts(1000, [1, 1, 1, 1, 1])], night: true);
      expect(s.any((x) => x.busier), isFalse);
      expect(s[0].recommended, isTrue);
    });

    test('failed lookups: busyness unknown, fastest recommended', () {
      final s = scoreRoutes([facts(900, [null, null]), facts(1000, [5, 5])], night: true);
      expect(s.first.busynessKnown, isFalse);
      expect(s.any((x) => x.busier), isFalse);
      expect(s[0].recommended, isTrue);
    });

    test('partial lookups still give a density', () {
      expect(facts(900, [4, null, 6]).placeDensity, 5);
    });

    test('fastest is found even when it is not first', () {
      final s = scoreRoutes([facts(1200, [3, 3]), facts(800, [3, 3]), facts(1000, [3, 3])], night: false);
      expect(s[1].fastest, isTrue);
      expect(s[1].recommended, isTrue);
    });

    test('single route is fastest and recommended', () {
      final s = scoreRoutes([facts(600, [4])], night: true);
      expect(s.single.fastest, isTrue);
      expect(s.single.recommended, isTrue);
      expect(s.single.busier, isFalse);
    });

    test('traffic ratio is never below 1', () {
      expect(facts(800, [1], staticDur: 1000).trafficRatio, 1.0);
      expect(facts(1500, [1], staticDur: 1000).trafficRatio, 1.5);
    });
  });

  group('formatting', () {
    test('durations and distances', () {
      expect(formatDuration(1080), '18 min');
      expect(formatDuration(3900), '1 h 05 min');
      expect(formatDistance(850), '850 m');
      expect(formatDistance(4200), '4.2 km');
    });
  });
}
