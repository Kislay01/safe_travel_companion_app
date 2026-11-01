import 'dart:math';

/// Pure geometry + scoring used by the busier-route suggestion and the
/// journey screen. No Flutter or plugin imports, so it is unit-testable.

class GeoPt {
  final double lat;
  final double lng;
  const GeoPt(this.lat, this.lng);
  @override
  String toString() => 'GeoPt($lat, $lng)';
}

const double _earthR = 6371000.0;
double _rad(double d) => d * pi / 180.0;

/// Great-circle distance in metres.
double haversine(GeoPt a, GeoPt b) {
  final dLat = _rad(b.lat - a.lat);
  final dLng = _rad(b.lng - a.lng);
  final h = sin(dLat / 2) * sin(dLat / 2) +
      cos(_rad(a.lat)) * cos(_rad(b.lat)) * sin(dLng / 2) * sin(dLng / 2);
  return 2 * _earthR * atan2(sqrt(h), sqrt(1 - h));
}

/// Total length of a polyline in metres.
double pathLength(List<GeoPt> pts) {
  var d = 0.0;
  for (var i = 1; i < pts.length; i++) {
    d += haversine(pts[i - 1], pts[i]);
  }
  return d;
}

/// [count] points spread evenly along the route by distance, ignoring the
/// first and last [skipFraction] (start and destination areas look the same on
/// every alternative, so they don't help compare routes).
List<GeoPt> samplePoints(List<GeoPt> pts, int count, {double skipFraction = 0.1}) {
  if (pts.isEmpty || count <= 0) return const [];
  if (pts.length == 1) return [pts.first];
  final cum = <double>[0];
  for (var i = 1; i < pts.length; i++) {
    cum.add(cum.last + haversine(pts[i - 1], pts[i]));
  }
  final total = cum.last;
  if (total == 0) return [pts.first];
  final start = total * skipFraction;
  final end = total * (1 - skipFraction);
  final out = <GeoPt>[];
  var seg = 1;
  for (var k = 0; k < count; k++) {
    final target = count == 1 ? (start + end) / 2 : start + (end - start) * k / (count - 1);
    while (seg < cum.length - 1 && cum[seg] < target) {
      seg++;
    }
    final segLen = cum[seg] - cum[seg - 1];
    final t = segLen == 0 ? 0.0 : ((target - cum[seg - 1]) / segLen).clamp(0.0, 1.0);
    final a = pts[seg - 1], b = pts[seg];
    out.add(GeoPt(a.lat + (b.lat - a.lat) * t, a.lng + (b.lng - a.lng) * t));
  }
  return out;
}

/// Metres still to travel along the route from [pos]: the closest point on the
/// route, then along the remaining segments to the end.
double remainingMeters(List<GeoPt> pts, GeoPt pos) {
  if (pts.isEmpty) return 0;
  if (pts.length == 1) return haversine(pos, pts.first);
  const mPerLat = 111320.0;
  final mPerLng = 111320.0 * cos(_rad(pos.lat));
  var bestSeg = 0;
  var bestT = 0.0;
  var bestD = double.infinity;
  for (var i = 1; i < pts.length; i++) {
    final ax = (pts[i - 1].lng - pos.lng) * mPerLng, ay = (pts[i - 1].lat - pos.lat) * mPerLat;
    final bx = (pts[i].lng - pos.lng) * mPerLng, by = (pts[i].lat - pos.lat) * mPerLat;
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    final t = len2 == 0 ? 0.0 : ((-ax * dx - ay * dy) / len2).clamp(0.0, 1.0);
    final px = ax + t * dx, py = ay + t * dy;
    final d = sqrt(px * px + py * py);
    if (d < bestD) {
      bestD = d;
      bestSeg = i;
      bestT = t;
    }
  }
  final a = pts[bestSeg - 1], b = pts[bestSeg];
  final proj = GeoPt(a.lat + (b.lat - a.lat) * bestT, a.lng + (b.lng - a.lng) * bestT);
  var rem = haversine(proj, b);
  for (var i = bestSeg + 1; i < pts.length; i++) {
    rem += haversine(pts[i - 1], pts[i]);
  }
  return rem;
}

/// Evenings and nights, when a busier road matters most.
bool isNight(DateTime t) => t.hour >= 19 || t.hour < 6;

/// What we know about one alternative route.
class RouteFacts {
  final int durationSeconds; // with live traffic
  final int staticDurationSeconds; // without traffic
  final int distanceMeters;

  /// Open-to-the-public places found around each sample point; null = lookup failed.
  final List<int?> placeCounts;

  const RouteFacts({
    required this.durationSeconds,
    required this.staticDurationSeconds,
    required this.distanceMeters,
    required this.placeCounts,
  });

  /// Average places per sample point (null when no lookup succeeded).
  double? get placeDensity {
    final ok = placeCounts.whereType<int>().toList();
    if (ok.isEmpty) return null;
    return ok.reduce((a, b) => a + b) / ok.length;
  }

  /// ≥ 1.0; how much slower than free-flow the road is right now (more traffic = more people around).
  double get trafficRatio {
    if (staticDurationSeconds <= 0) return 1.0;
    return max(1.0, durationSeconds / staticDurationSeconds);
  }
}

class RouteScore {
  final int index;
  final double busyness; // 0..1 relative to the other options
  final bool fastest;
  final bool busier; // clearly busier than the fastest route
  final bool recommended;
  final bool busynessKnown;
  const RouteScore({
    required this.index,
    required this.busyness,
    required this.fastest,
    required this.busier,
    required this.recommended,
    required this.busynessKnown,
  });
}

/// Scores alternatives: 70% density of places along the way, 30% live traffic.
///
/// A route counts as "busier" only if it has at least 15% more places per
/// sample point than the fastest route (and at least 0.5 more), so tiny
/// differences never get a badge. At night the busier route is recommended
/// if it costs at most 25% (and at most 10 minutes) more time; otherwise the
/// fastest route is recommended.
List<RouteScore> scoreRoutes(List<RouteFacts> routes, {required bool night}) {
  if (routes.isEmpty) return const [];
  final n = routes.length;
  var fastest = 0;
  for (var i = 1; i < n; i++) {
    if (routes[i].durationSeconds < routes[fastest].durationSeconds) fastest = i;
  }
  final dens = routes.map((r) => r.placeDensity).toList();
  final known = dens.every((d) => d != null);
  final maxDen = known ? dens.map((d) => d!).reduce(max) : 0.0;
  final maxRatio = routes.map((r) => r.trafficRatio).reduce(max);

  final busy = List<double>.generate(n, (i) {
    final dNorm = (!known || maxDen <= 0) ? 0.0 : dens[i]! / maxDen;
    final tNorm = maxRatio <= 1.0 ? 0.0 : (routes[i].trafficRatio - 1.0) / (maxRatio - 1.0);
    return known ? 0.7 * dNorm + 0.3 * tNorm : tNorm;
  });

  var busiest = 0;
  for (var i = 1; i < n; i++) {
    if (busy[i] > busy[busiest]) busiest = i;
  }
  var busierIdx = -1;
  if (known && busiest != fastest) {
    final b = dens[busiest]!, f = dens[fastest]!;
    if (b >= f * 1.15 && b - f >= 0.5) busierIdx = busiest;
  }

  var rec = fastest;
  if (night && busierIdx >= 0) {
    final extra = routes[busierIdx].durationSeconds - routes[fastest].durationSeconds;
    if (routes[busierIdx].durationSeconds <= routes[fastest].durationSeconds * 1.25 && extra <= 600) {
      rec = busierIdx;
    }
  }

  return List<RouteScore>.generate(
    n,
    (i) => RouteScore(
      index: i,
      busyness: busy[i],
      fastest: i == fastest,
      busier: i == busierIdx,
      recommended: i == rec,
      busynessKnown: known,
    ),
  );
}

/// "1 h 05 min" / "18 min".
String formatDuration(int seconds) {
  final m = (seconds / 60).round();
  if (m < 60) return '$m min';
  return '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')} min';
}

/// "4.2 km" / "850 m".
String formatDistance(num meters) =>
    meters >= 1000 ? '${(meters / 1000).toStringAsFixed(1)} km' : '${meters.round()} m';
