import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:sos_system/core/app_theme.dart';
import 'package:sos_system/services/places_service.dart';
import 'package:sos_system/services/saved_places_service.dart';
import 'package:uuid/uuid.dart';

/// Bottom sheet to save a place: pick a label, then search or use the current location.
Future<bool?> showAddPlaceSheet(BuildContext context, {required String email, String? initialLabel}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: TG.surfaceOf(context),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _AddPlaceSheet(email: email, initialLabel: initialLabel),
  );
}

class _AddPlaceSheet extends StatefulWidget {
  final String email;
  final String? initialLabel;
  const _AddPlaceSheet({required this.email, this.initialLabel});

  @override
  State<_AddPlaceSheet> createState() => _AddPlaceSheetState();
}

class _AddPlaceSheetState extends State<_AddPlaceSheet> {
  final _labelCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  String _label = 'Home';
  bool _custom = false;

  Timer? _debounce;
  String _session = const Uuid().v4();
  List<PlaceSuggestion> _suggestions = [];
  bool _busy = false;
  String? _error;
  LatLng? _near;

  @override
  void initState() {
    super.initState();
    final l = widget.initialLabel;
    if (l != null && l.isNotEmpty) {
      if (SavedPlacesService.presetLabels.contains(l)) {
        _label = l;
      } else {
        _custom = true;
        _labelCtrl.text = l;
      }
    }
    Geolocator.getLastKnownPosition().then((p) {
      if (p != null && mounted) _near = LatLng(p.latitude, p.longitude);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _labelCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  String get _chosenLabel => _custom ? _labelCtrl.text : _label;

  void _onSearch(String text) {
    _debounce?.cancel();
    if (text.trim().length < 2) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final r = await PlacesService.autocomplete(text, sessionToken: _session, near: _near);
      if (mounted) setState(() => _suggestions = r);
    });
  }

  Future<void> _save(String name, String address, LatLng loc) async {
    final label = SavedPlacesService.normalizeLabel(_chosenLabel);
    if (label.isEmpty) {
      setState(() => _error = 'Give this place a name, e.g. “Gym”.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SavedPlacesService.save(
        email: widget.email,
        label: label,
        name: name,
        address: address,
        location: loc,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e is StateError ? e.message : 'Could not save. Check your internet.';
        });
      }
    }
  }

  Future<void> _pickSuggestion(PlaceSuggestion s) async {
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    final d = await PlacesService.details(s.placeId, sessionToken: _session);
    _session = const Uuid().v4();
    if (!mounted) return;
    if (d == null) {
      setState(() {
        _busy = false;
        _error = "Couldn't load that place. Try again.";
      });
      return;
    }
    await _save(s.mainText, d.address.isNotEmpty ? d.address : s.fullText, d.location);
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        final asked = await Geolocator.requestPermission();
        if (asked == LocationPermission.denied || asked == LocationPermission.deniedForever) {
          throw StateError('Location permission is needed to use your current location.');
        }
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      var name = 'Current location';
      var address = '';
      try {
        final marks = await placemarkFromCoordinates(p.latitude, p.longitude);
        if (marks.isNotEmpty) {
          final m = marks.first;
          name = [m.subLocality, m.locality].where((e) => e != null && e.isNotEmpty).join(', ');
          if (name.isEmpty) name = 'Current location';
          address = [m.name, m.subLocality, m.locality].where((e) => e != null && e.isNotEmpty).join(', ');
        }
      } catch (_) {}
      await _save(name, address, LatLng(p.latitude, p.longitude));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e is StateError ? e.message : "Couldn't get your location. Try again outdoors.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = TG.inkOf(context), muted = TG.mutedOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: TG.lineOf(context), borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Text('Save a place', style: GoogleFonts.manrope(fontSize: 20, fontWeight: FontWeight.w800, color: ink)),
          const SizedBox(height: 4),
          Text('Start a journey there with one tap.', style: TextStyle(fontSize: 13, color: muted)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final l in SavedPlacesService.presetLabels)
                ChoiceChip(
                  avatar: Icon(SavedPlacesService.iconFor(l), size: 18),
                  label: Text(l),
                  selected: !_custom && _label == l,
                  onSelected: (_) => setState(() {
                    _custom = false;
                    _label = l;
                  }),
                ),
              ChoiceChip(
                avatar: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Other'),
                selected: _custom,
                onSelected: (_) => setState(() => _custom = true),
              ),
            ],
          ),
          if (_custom) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _labelCtrl,
              textCapitalization: TextCapitalization.words,
              maxLength: 20,
              decoration: const InputDecoration(labelText: 'Name this place', hintText: 'e.g. Gym, Tuition'),
            ),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: _searchCtrl,
            onChanged: _onSearch,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search for the place',
            ),
          ),
          if (_suggestions.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _suggestions.length,
                itemBuilder: (_, i) {
                  final s = _suggestions[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.place_outlined, color: TG.teal),
                    title: Text(s.mainText, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: s.secondaryText.isEmpty
                        ? null
                        : Text(s.secondaryText, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: _busy ? null : () => _pickSuggestion(s),
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _useCurrentLocation,
            icon: const Icon(Icons.my_location),
            label: const Text("I'm here now: use my current location"),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: TG.sos, fontWeight: FontWeight.w600)),
          ],
          if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
        ],
      ),
    );
  }
}
