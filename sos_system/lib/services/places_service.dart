import 'dart:async';
import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:sos_system/core/app_config.dart';

class PlaceSuggestion {
  final String placeId;
  final String mainText;
  final String secondaryText;
  const PlaceSuggestion(this.placeId, this.mainText, this.secondaryText);
  String get fullText => secondaryText.isEmpty ? mainText : '$mainText, $secondaryText';
}

class PlaceDetails {
  final String name;
  final String address;
  final LatLng location;
  const PlaceDetails(this.name, this.address, this.location);
}

/// Places API (New): type-ahead suggestions + coordinates of the chosen place.
/// Pass the same session token to autocomplete() and details() for one search;
/// Google then bills it as a single session (suggestions are free).
class PlacesService {
  PlacesService._();

  static const _base = 'https://places.googleapis.com/v1';

  static Future<List<PlaceSuggestion>> autocomplete(
    String input, {
    required String sessionToken,
    LatLng? near,
  }) async {
    if (!AppConfig.hasMapsKey || input.trim().length < 2) return [];
    final body = <String, dynamic>{
      'input': input.trim(),
      'sessionToken': sessionToken,
      'includedRegionCodes': ['in'],
      'languageCode': 'en',
    };
    if (near != null) {
      body['locationBias'] = {
        'circle': {
          'center': {'latitude': near.latitude, 'longitude': near.longitude},
          'radius': 50000.0,
        }
      };
    }
    try {
      final res = await http
          .post(
            Uri.parse('$_base/places:autocomplete'),
            headers: {
              'Content-Type': 'application/json',
              'X-Goog-Api-Key': AppConfig.mapsApiKey,
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (data['suggestions'] as List?) ?? [];
      final out = <PlaceSuggestion>[];
      for (final s in list) {
        final p = (s as Map)['placePrediction'] as Map?;
        if (p == null) continue;
        final fmt = p['structuredFormat'] as Map?;
        final main = ((fmt?['mainText'] as Map?)?['text'] ??
                (p['text'] as Map?)?['text'] ??
                '')
            .toString();
        final secondary = ((fmt?['secondaryText'] as Map?)?['text'] ?? '').toString();
        out.add(PlaceSuggestion(p['placeId'].toString(), main, secondary));
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  static Future<PlaceDetails?> details(String placeId, {required String sessionToken}) async {
    if (!AppConfig.hasMapsKey) return null;
    try {
      final uri = Uri.parse('$_base/places/$placeId')
          .replace(queryParameters: {'sessionToken': sessionToken});
      final res = await http.get(uri, headers: {
        'X-Goog-Api-Key': AppConfig.mapsApiKey,
        'X-Goog-FieldMask': 'displayName,formattedAddress,location',
      }).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final d = jsonDecode(res.body) as Map<String, dynamic>;
      final loc = d['location'] as Map?;
      if (loc == null) return null;
      return PlaceDetails(
        ((d['displayName'] as Map?)?['text'] ?? '').toString(),
        (d['formattedAddress'] ?? '').toString(),
        LatLng((loc['latitude'] as num).toDouble(), (loc['longitude'] as num).toDouble()),
      );
    } catch (_) {
      return null;
    }
  }
}
