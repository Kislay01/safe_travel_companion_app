import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:sos_system/core/user_paths.dart';

/// A place the traveller goes to often (Home, College, Hostel…).
///
/// Firestore: Child/{email}/saved_places/{id}
///   {label, name, address, lat, lng, createdAt}
class SavedPlace {
  final String id;
  final String label;
  final String name;
  final String address;
  final LatLng location;

  const SavedPlace({
    required this.id,
    required this.label,
    required this.name,
    required this.address,
    required this.location,
  });

  /// Label shown on chips ("Home"); falls back to the place name.
  String get title => label.trim().isNotEmpty ? label.trim() : name;

  IconData get icon => SavedPlacesService.iconFor(label);

  static SavedPlace? fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    if (m == null || m['lat'] is! num || m['lng'] is! num) return null;
    return SavedPlace(
      id: d.id,
      label: (m['label'] ?? '').toString(),
      name: (m['name'] ?? '').toString(),
      address: (m['address'] ?? '').toString(),
      location: LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble()),
    );
  }
}

class SavedPlacesService {
  SavedPlacesService._();

  /// Keeps the home screen chips row short and Firestore reads small.
  static const int maxPlaces = 8;

  static const presetLabels = ['Home', 'College', 'Hostel', 'Work'];

  /// Set by a home-screen chip; the Journey tab picks it up as its destination.
  static final ValueNotifier<SavedPlace?> pendingDestination = ValueNotifier(null);

  static CollectionReference<Map<String, dynamic>> _col(String email) =>
      UserPaths.child(email).collection('saved_places');

  static Stream<List<SavedPlace>> watch(String email) {
    if (email.isEmpty) return Stream.value(const []);
    return _col(email).orderBy('createdAt').snapshots().map(
          (s) => s.docs.map(SavedPlace.fromDoc).whereType<SavedPlace>().toList(),
        );
  }

  /// Saves a place. Re-using a label (e.g. a second "Home") replaces the old one.
  static Future<void> save({
    required String email,
    required String label,
    required String name,
    required String address,
    required LatLng location,
  }) async {
    if (email.isEmpty) throw StateError('Not signed in');
    final col = _col(email);
    final cleanLabel = normalizeLabel(label);
    final existing = await col.get();
    final sameLabel = existing.docs.where(
      (d) => normalizeLabel((d.data()['label'] ?? '').toString()).toLowerCase() == cleanLabel.toLowerCase(),
    );
    if (sameLabel.isEmpty && existing.docs.length >= maxPlaces) {
      throw StateError('You can save up to $maxPlaces places. Remove one first.');
    }
    final data = {
      'label': cleanLabel,
      'name': name.trim(),
      'address': address.trim(),
      'lat': location.latitude,
      'lng': location.longitude,
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (sameLabel.isNotEmpty) {
      data.remove('createdAt'); // keep its place in the row
      await sameLabel.first.reference.set(data, SetOptions(merge: true));
    } else {
      await col.add(data);
    }
  }

  static Future<void> remove(String email, String id) => _col(email).doc(id).delete();

  /// "  home " → "Home"; empty stays empty.
  static String normalizeLabel(String raw) {
    final t = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.isEmpty) return '';
    return t[0].toUpperCase() + t.substring(1);
  }

  static IconData iconFor(String label) {
    switch (label.trim().toLowerCase()) {
      case 'home':
        return Icons.home_outlined;
      case 'college':
      case 'school':
      case 'university':
        return Icons.school_outlined;
      case 'hostel':
      case 'pg':
        return Icons.apartment_outlined;
      case 'work':
      case 'office':
        return Icons.work_outline;
      default:
        return Icons.place_outlined;
    }
  }
}
