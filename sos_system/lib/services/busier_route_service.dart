import 'dart:async';
import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:sos_system/core/app_config.dart';
import 'package:sos_system/services/route_scoring.dart';
import 'package:sos_system/services/routes_service.dart';

/// One alternative, ready to show: the route plus how busy it is.
class RouteOption {
  final RouteResult route;
  final RouteFacts facts;
  final RouteScore score;
  const RouteOption(this.route, this.facts, this.score);

  /// Short, honest label. Never "safe": we can only say "busier".
  String get badge {
    if (score.fastest && score.recommended && !score.busier) return 'Fastest';
    if (score.busier) return 'Busier route';
    if (score.fastest) return 'Fastest';
    return 'Alternative';
  }

  String get detail {
    final d = facts.placeDensity;
    final places = d == null ? '' : ' · ~${d.round()} open places per stop checked';
    return '${formatDuration(route.durationSeconds)} · ${formatDistance(route.distanceMeters)}$places';
  }
}

class BusierRouteResult {
  final List<RouteOption> options;
  final bool night;
  final bool busynessChecked;
  const BusierRouteResult(this.options, {required this.night, required this.busynessChecked});

  RouteOption get recommended => options.firstWhere((o) => o.score.recommended, orElse: () => options.first);
}

/// Compares alternative routes by how busy they are: places open to the public
/// along the way (shops, pharmacies, petrol pumps, transit…) and live traffic.
/// Busier roads mean more people around, especially at night. It never claims
/// a route is "safe".
class BusierRouteService {
  BusierRouteService._();

  /// Points checked per route; 3 routes × 5 = at most 15 Nearby Search calls,
  /// fewer when routes overlap (results are cached per ~110 m grid cell).
  static const int samplesPerRoute = 5;
  static const double sampleRadiusMeters = 250;

  static const _types = [
    'restaurant',
    'cafe',
    'pharmacy',
    'hospital',
    'police',
    'gas_station',
    'convenience_store',
    'supermarket',
    'atm',
    'bus_station',
    'transit_station',
    'shopping_mall',
  ];

  static final Map<String, int> _cache = {};

  static Future<BusierRouteResult> compare({
    required LatLng origin,
    required LatLng destination,
    DateTime? now,
  }) async {
    final routes = await RoutesService.computeAlternatives(origin: origin, destination: destination);
    final night = isNight(now ?? DateTime.now());

    final facts = <RouteFacts>[];
    for (final r in routes) {
      final pts = r.points.map((p) => GeoPt(p.latitude, p.longitude)).toList();
      final samples = samplePoints(pts, samplesPerRoute);
      final counts = await Future.wait(samples.map(_placesNear));
      facts.add(RouteFacts(
        durationSeconds: r.durationSeconds,
        staticDurationSeconds: r.staticDurationSeconds,
        distanceMeters: r.distanceMeters,
        placeCounts: counts,
      ));
    }
    final scores = scoreRoutes(facts, night: night);
    final options = [for (var i = 0; i < routes.length; i++) RouteOption(routes[i], facts[i], scores[i])];
    // Recommended first, then by duration.
    options.sort((a, b) {
      if (a.score.recommended != b.score.recommended) return a.score.recommended ? -1 : 1;
      return a.route.durationSeconds.compareTo(b.route.durationSeconds);
    });
    return BusierRouteResult(options, night: night, busynessChecked: scores.isNotEmpty && scores.first.busynessKnown);
  }

  static String _cell(GeoPt p) => '${p.lat.toStringAsFixed(3)},${p.lng.toStringAsFixed(3)}';

  /// Number of matching places within [sampleRadiusMeters] (max 20), or null if the lookup failed.
  static Future<int?> _placesNear(GeoPt p) async {
    final key = _cell(p);
    final hit = _cache[key];
    if (hit != null) return hit;
    if (!AppConfig.hasMapsKey) return null;
    try {
      final res = await http
          .post(
            Uri.parse('https://places.googleapis.com/v1/places:searchNearby'),
            headers: {
              'Content-Type': 'application/json',
              'X-Goog-Api-Key': AppConfig.mapsApiKey,
              'X-Goog-FieldMask': 'places.id',
            },
            body: jsonEncode({
              'includedTypes': _types,
              'maxResultCount': 20,
              'locationRestriction': {
                'circle': {
                  'center': {'latitude': p.lat, 'longitude': p.lng},
                  'radius': sampleRadiusMeters,
                },
              },
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final data = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body) as Map<String, dynamic>;
      final n = ((data['places'] as List?) ?? const []).length;
      _cache[key] = n;
      return n;
    } catch (_) {
      return null;
    }
  }
}
