import 'dart:async';
import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:sos_system/core/app_config.dart';

/// One turn-by-turn step: what to say, and where the step ends.
class RouteStep {
  final String instruction;
  final LatLng end;
  const RouteStep(this.instruction, this.end);
}

class RouteResult {
  final String encodedPolyline;
  final List<LatLng> points;
  final List<RouteStep> steps;
  final int distanceMeters;
  final int durationSeconds;

  /// Duration without live traffic (equals [durationSeconds] when traffic wasn't requested).
  final int staticDurationSeconds;
  const RouteResult({
    required this.encodedPolyline,
    required this.points,
    required this.steps,
    required this.distanceMeters,
    required this.durationSeconds,
    int? staticDurationSeconds,
  }) : staticDurationSeconds = staticDurationSeconds ?? durationSeconds;
}

class RoutesException implements Exception {
  final String message;
  RoutesException(this.message);
  @override
  String toString() => message;
}

/// Google Routes API (replaces the legacy Directions API).
class RoutesService {
  RoutesService._();

  static const _endpoint =
      'https://routes.googleapis.com/directions/v2:computeRoutes';
  static const _fieldMask = 'routes.distanceMeters,routes.duration,routes.staticDuration,'
      'routes.polyline.encodedPolyline,'
      'routes.legs.steps.navigationInstruction,routes.legs.steps.endLocation';

  /// One route (used when starting without options and for automatic re-routing).
  static Future<RouteResult> computeRoute({
    required LatLng origin,
    required LatLng destination,
    String travelMode = 'DRIVE',
  }) async {
    final list = await _compute(origin: origin, destination: destination, travelMode: travelMode);
    return list.first;
  }

  /// Up to 3 alternative routes with live-traffic durations. The order is
  /// not guaranteed to be fastest-first, so callers compare durations.
  static Future<List<RouteResult>> computeAlternatives({
    required LatLng origin,
    required LatLng destination,
  }) {
    return _compute(
      origin: origin,
      destination: destination,
      travelMode: 'DRIVE',
      alternatives: true,
      trafficAware: true,
    );
  }

  static Future<List<RouteResult>> _compute({
    required LatLng origin,
    required LatLng destination,
    required String travelMode,
    bool alternatives = false,
    bool trafficAware = false,
  }) async {
    if (!AppConfig.hasMapsKey) {
      throw RoutesException(
          'Maps key missing. Run with --dart-define-from-file=secrets.json');
    }

    final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Content-Type': 'application/json',
              'X-Goog-Api-Key': AppConfig.mapsApiKey,
              'X-Goog-FieldMask': _fieldMask,
            },
            body: jsonEncode({
              'origin': _waypoint(origin),
              'destination': _waypoint(destination),
              'travelMode': travelMode,
              'languageCode': 'en',
              'units': 'METRIC',
              if (alternatives) 'computeAlternativeRoutes': true,
              if (trafficAware) 'routingPreference': 'TRAFFIC_AWARE',
            }),
          )
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw RoutesException('Route request timed out. Check your internet.');
    }

    if (res.statusCode == 429) {
      throw RoutesException('Too many route requests. Try again in a minute.');
    }
    final Map<String, dynamic> data =
        res.body.isEmpty ? {} : jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      final msg = (data['error'] as Map?)?['message'] ?? 'HTTP ${res.statusCode}';
      throw RoutesException('Route error: $msg');
    }

    final routes = data['routes'] as List?;
    if (routes == null || routes.isEmpty) {
      throw RoutesException('No route found to this destination.');
    }
    return routes.map((r) => _parse(r as Map<String, dynamic>)).toList();
  }

  static int _seconds(Object? v) =>
      int.tryParse((v as String? ?? '0s').replaceAll('s', '').split('.').first) ?? 0;

  static RouteResult _parse(Map<String, dynamic> route) {
    final steps = <RouteStep>[];
    for (final leg in (route['legs'] as List? ?? [])) {
      for (final s in ((leg as Map)['steps'] as List? ?? [])) {
        final text =
            ((s as Map)['navigationInstruction'] as Map?)?['instructions'] as String?;
        final ll = (s['endLocation'] as Map?)?['latLng'] as Map?;
        if (text == null || text.isEmpty || ll == null) continue;
        steps.add(RouteStep(
          text,
          LatLng((ll['latitude'] as num).toDouble(),
              (ll['longitude'] as num).toDouble()),
        ));
      }
    }

    final encoded =
        (route['polyline'] as Map?)?['encodedPolyline'] as String? ?? '';
    final duration = _seconds(route['duration']);
    final staticDuration = route.containsKey('staticDuration') ? _seconds(route['staticDuration']) : duration;

    return RouteResult(
      encodedPolyline: encoded,
      points: decodePolyline(encoded),
      steps: steps,
      distanceMeters: (route['distanceMeters'] as num?)?.toInt() ?? 0,
      durationSeconds: duration,
      staticDurationSeconds: staticDuration,
    );
  }

  static Map<String, dynamic> _waypoint(LatLng p) => {
        'location': {
          'latLng': {'latitude': p.latitude, 'longitude': p.longitude}
        }
      };

  /// Google encoded polyline → points.
  static List<LatLng> decodePolyline(String encoded) {
    final points = <LatLng>[];
    int index = 0, lat = 0, lng = 0;
    while (index < encoded.length) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }
}
