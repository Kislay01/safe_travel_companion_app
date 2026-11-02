import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sos_system/core/app_theme.dart';
import 'package:sos_system/services/route_scoring.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart' as location_pkg;
import 'package:geocoding/geocoding.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:sos_system/common/views/custom_appbar.dart';
import 'package:sos_system/services/routes_service.dart';
import 'package:sos_system/common/views/custom_snackbar.dart';
import 'package:sos_system/core/user_paths.dart';
import 'package:sos_system/modules/guardian/views/checkin_status_dialog.dart';

class TrackChild extends StatefulWidget {
  final String guardianEmail; // pass guardian email to filter connected children
  final String? initialChildEmail;
  const TrackChild({super.key, required this.guardianEmail, this.initialChildEmail});

  @override
  State<TrackChild> createState() => _TrackChildState();
}

class _TrackChildState extends State<TrackChild> {
  final location_pkg.Location _location = location_pkg.Location();
  GoogleMapController? _mapController;

  LatLng? _currentLocation;
  LatLng? _destination; // used when we draw a route to the child

  String? _currentAddress;
  String? _currentShort;
  String? _destinationAddress;

  // final TextEditingController _searchController = TextEditingController();

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  bool _isLoading = false;
  bool _journeyStarted = false;

  StreamSubscription<location_pkg.LocationData>? _locationSubscription;
  StreamSubscription<CompassEvent>? _compassSubscription;

  late BitmapDescriptor _carIcon;
  late FlutterTts _flutterTts;

  List<LatLng> _routePoints = [];
  final List<RouteStep> _routeSteps = [];
  int _currentStepIndex = 0;

  double _deviceHeading = 0.0;
  double _lastLat = 0.0;
  double _lastLng = 0.0;

  // Firestore subscription for selected child's live location
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _childLiveSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _childDocSub;
  String? _selectedChildEmail;
  String _selectedChildName = '';
  Map<String, dynamic>? _childJourney; // active journey of the selected child
  Marker? _childLiveMarker;
  String _selectedChildPhone = '';
  int? _childSeenMs;
  bool _childGpsOk = true;
  LatLng? _childPos;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await Future.wait([_loadCarIcon(), _fetchCurrentLocation()]);
    _initTts();
    _listenCompass();
    await _autoSelectChild();
  }

  void _initTts() {
    _flutterTts = FlutterTts();
    _flutterTts.setLanguage("en-US");
    _flutterTts.setSpeechRate(0.45);
    _flutterTts.setVolume(1.0);
    _flutterTts.setPitch(1.0);
  }

  void _listenCompass() {
    _compassSubscription = FlutterCompass.events?.listen((event) {
      if (event.heading != null) {
        _deviceHeading = event.heading!;
      }
    });
  }

  @override
  void dispose() {
    _compassSubscription?.cancel();
    _locationSubscription?.cancel();
    _childLiveSub?.cancel();
    _childDocSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _loadCarIcon() async {
    try {
      _carIcon = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(64, 64)),
        "assets/images/car_arrow.png",
      );
    } catch (e) {
      debugPrint("Error loading car icon: $e");
      _carIcon = BitmapDescriptor.defaultMarker;
    }
  }

  Future<void> _fetchCurrentLocation() async {
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) return;
    }

    var permission = await _location.hasPermission();
    if (permission == location_pkg.PermissionStatus.denied) {
      permission = await _location.requestPermission();
      if (permission != location_pkg.PermissionStatus.granted) return;
    }

    final loc = await _location.getLocation();
    _currentLocation = LatLng(loc.latitude!, loc.longitude!);

    try {
      final placemarks = await placemarkFromCoordinates(
        loc.latitude!,
        loc.longitude!,
      );
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        _currentAddress =
            "${p.name ?? ""}, ${p.locality ?? ""}, ${p.subAdministrativeArea ?? ""}";
        _currentShort =
            "${p.subLocality ?? p.name ?? ""}, ${p.locality ?? p.administrativeArea ?? ""}";
      }
    } catch (e) {
      debugPrint("Address fetch error: $e");
    }

    if (mounted) setState(() {});
  }

  // Future<void> _searchDestination(String query) async {
  //   if (query.trim().isEmpty) return;
  //   try {
  //     final locations = await locationFromAddress(query);
  //     if (locations.isEmpty) {
  //       ScaffoldMessenger.of(
  //         context,
  //       ).showSnackBar(const SnackBar(content: Text("No location found")));
  //       return;
  //     }
  //     final loc = locations.first;
  //     _destination = LatLng(loc.latitude, loc.longitude);
  //     _destinationAddress = query;

  //     _markers.removeWhere((m) => m.markerId.value == 'destination');
  //     _markers.add(
  //       Marker(
  //         markerId: const MarkerId('destination'),
  //         position: _destination!,
  //         infoWindow: InfoWindow(title: query),
  //       ),
  //     );

  //     if (_currentLocation != null) {
  //       final bounds = _boundsFromLatLngList([
  //         _currentLocation!,
  //         _destination!,
  //       ]);
  //       _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
  //     } else {
  //       _mapController?.animateCamera(
  //         CameraUpdate.newLatLngZoom(_destination!, 14),
  //       );
  //     }

  //     if (mounted) setState(() {});
  //   } catch (e) {
  //     debugPrint("Search error: $e");
  //   }
  // }

  /// Start route calculation from current location to destination (child)
  Future<void> _startJourney() async {
    if (_currentLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Current location unavailable")),
      );
      return;
    }

    // If destination isn't set yet (like when tracking a child), use selected child's live marker
    if (_destination == null && _childLiveMarker != null) {
      _destination = _childLiveMarker!.position;
      _destinationAddress = _selectedChildEmail ?? "Child";
    }

    if (_destination == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please set a destination first")),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _journeyStarted = true;
      _routeSteps.clear();
      _currentStepIndex = 0;
    });

    try {
      final route = await RoutesService.computeRoute(
        origin: _currentLocation!,
        destination: _destination!,
      );
      _routePoints = route.points;
      _routeSteps
        ..clear()
        ..addAll(route.steps);
      if (_routeSteps.isNotEmpty) {
        _flutterTts.speak(_routeSteps.first.instruction);
      }

      _polylines.removeWhere((p) => p.polylineId.value == 'route');
      _polylines.add(
        Polyline(
          polylineId: const PolylineId("route"),
          color: const Color(0xFF4F5F5C),
          width: 5,
          patterns: [PatternItem.dash(18), PatternItem.gap(10)],
          points: _routePoints,
        ),
      );

      if (_routePoints.isNotEmpty) {
        final b = _boundsFromLatLngList(_routePoints);
        _mapController?.animateCamera(CameraUpdate.newLatLngBounds(b, 80));
      }

      _startTracking();
    } on RoutesException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
        setState(() {
          _isLoading = false;
          _journeyStarted = false;
        });
      }
      return;
    } catch (e) {
      debugPrint("Error fetching route: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Could not get a route. Try again.")));
        setState(() {
          _isLoading = false;
          _journeyStarted = false;
        });
      }
      return;
    }

    setState(() => _isLoading = false);
  }

  void _startTracking() {
    _location.changeSettings(interval: 1000, distanceFilter: 2);

    _locationSubscription = _location.onLocationChanged.listen((loc) {
      if (loc.latitude == null || loc.longitude == null) return;
      final pos = LatLng(loc.latitude!, loc.longitude!);

      if (_lastLat != 0 && _lastLng != 0) {
        final distance = _distanceBetween(pos, LatLng(_lastLat, _lastLng));
        if (distance < 3) return;
      }
      _lastLat = pos.latitude;
      _lastLng = pos.longitude;

      _markers.removeWhere((m) => m.markerId.value == 'me');
      _markers.add(
        Marker(
          markerId: const MarkerId('me'),
          position: pos,
          rotation: _deviceHeading,
          icon: _carIcon,
          anchor: const Offset(0.5, 0.5),
        ),
      );
      _currentLocation = pos;

      _showNextInstruction(pos);

      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: pos,
            zoom: 17,
            tilt: 65,
            bearing: _deviceHeading,
          ),
        ),
      );

      if (mounted) setState(() {});
    });
  }

  /// Speaks the next instruction once the current step's end point is reached.
  void _showNextInstruction(LatLng currentPos) async {
    if (_currentStepIndex >= _routeSteps.length) return;

    final step = _routeSteps[_currentStepIndex];
    if (_distanceBetween(currentPos, step.end) < 25) {
      _currentStepIndex++;
      if (_currentStepIndex < _routeSteps.length) {
        await _flutterTts.speak(_routeSteps[_currentStepIndex].instruction);
      } else {
        await _flutterTts.speak("You have arrived at your destination");
      }
    }
  }

  double _distanceBetween(LatLng a, LatLng b) {
    const R = 6371000;
    double dLat = _deg2rad(b.latitude - a.latitude);
    double dLon = _deg2rad(b.longitude - a.longitude);
    double lat1 = _deg2rad(a.latitude);
    double lat2 = _deg2rad(b.latitude);

    double h =
        sin(dLat / 2) * sin(dLat / 2) +
        sin(dLon / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2);
    double c = 2 * atan2(sqrt(h), sqrt(1 - h));
    return R * c;
  }

  double _deg2rad(double deg) => deg * pi / 180;

  LatLngBounds _boundsFromLatLngList(List<LatLng> list) {
    double minLat = list.first.latitude;
    double maxLat = list.first.latitude;
    double minLng = list.first.longitude;
    double maxLng = list.first.longitude;

    for (final p in list) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  void _subscribeToChildLive(String childEmail, {String? name}) {
    _childLiveSub?.cancel();
    _selectedChildEmail = childEmail;
    if (name != null) _selectedChildName = name;
    _selectedChildPhone = '';
    _childSeenMs = null;
    _childPos = null;
    _childGpsOk = true;
    UserPaths.guardian(widget.guardianEmail)
        .collection('emergency_contacts')
        .doc(UserPaths.normalize(childEmail))
        .get()
        .then((d) {
      if (mounted && _selectedChildEmail == childEmail) {
        setState(() => _selectedChildPhone = (d.data()?['mobile'] ?? '').toString().trim());
      }
    }).catchError((_) {});
    _watchChildJourney(childEmail);
    _childLiveSub = FirebaseFirestore.instance
        .collection('Child')
        .doc(childEmail)
        .collection('live_location')
        .doc('current')
        .snapshots()
        .listen((snap) {
      if (!snap.exists) return;
      final data = snap.data();
      if (data == null) return;
      final ts = data['timestamp'];
      if (ts is num) _childSeenMs = ts.toInt();
      _childGpsOk = data['gpsOk'] != false;
      if (data['latitude'] is! num || data['longitude'] is! num) {
        if (mounted) setState(() {});
        return;
      }
      final lat = (data['latitude'] as num).toDouble();
      final lng = (data['longitude'] as num).toDouble();
      final childPos = LatLng(lat, lng);
      _childPos = childPos;

      _markers.removeWhere((m) => m.markerId.value == 'child_live');
      _childLiveMarker = Marker(
        markerId: const MarkerId('child_live'),
        position: childPos,
        infoWindow: InfoWindow(
            title: _selectedChildName.isNotEmpty ? _selectedChildName : _selectedChildEmail),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
      );
      _markers.add(_childLiveMarker!);

      if (!_journeyStarted) {
        _destination = childPos;
        _destinationAddress = "$_selectedChildEmail";
        _mapController?.animateCamera(CameraUpdate.newLatLngZoom(childPos, 16));
      }

      if (mounted) setState(() {});
    });
  }

  /// Picks [initialChildEmail], or the only linked child, automatically.
  Future<void> _autoSelectChild() async {
    if (!mounted) return;
    if (widget.initialChildEmail != null) {
      final kids = await UserPaths.childrenOf(widget.guardianEmail);
      final match = kids.where((d) => d.id == UserPaths.normalize(widget.initialChildEmail!));
      final name = match.isEmpty ? '' : (match.first.data()['name'] ?? '').toString();
      _subscribeToChildLive(widget.initialChildEmail!, name: name);
      return;
    }
    final kids = await UserPaths.childrenOf(widget.guardianEmail);
    if (kids.length == 1 && mounted) {
      _subscribeToChildLive(kids.first.id, name: (kids.first.data()['name'] ?? '').toString());
    }
  }

  Future<void> _showConnectedChildrenList() async {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return FutureBuilder(
          future: UserPaths.childrenOf(widget.guardianEmail),
          builder: (context, st) {
            if (!st.hasData) {
              return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
            }
            final list = st.data!;
            if (list.isEmpty) {
              return const SizedBox(height: 200, child: Center(child: Text("No connected children found")));
            }
            return ListView.builder(
              shrinkWrap: true,
              itemCount: list.length,
              itemBuilder: (context, index) {
                final doc = list[index];
                final name = (doc.data()['name'] ?? '').toString();
                return ListTile(
                  title: Text(name.isNotEmpty ? name : doc.id),
                  subtitle: Text(doc.id),
                  leading: const Icon(Icons.child_care),
                  onTap: () {
                    Navigator.pop(context);
                    _subscribeToChildLive(doc.id, name: name);
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  /// Draws the selected child's active journey (route + destination).
  void _watchChildJourney(String childEmail) {
    _childDocSub?.cancel();
    _childDocSub = UserPaths.child(childEmail).snapshots().listen((snap) async {
      final id = snap.data()?['activeJourneyId'] as String?;
      Map<String, dynamic>? journey;
      if (id != null && id.isNotEmpty) {
        final j = await UserPaths.child(childEmail).collection('journeys').doc(id).get();
        if (j.data()?['status'] == 'active') journey = j.data();
      }
      if (!mounted) return;
      setState(() {
        _childJourney = journey;
        _polylines.removeWhere((p) => p.polylineId.value == 'child_route');
        _markers.removeWhere((m) => m.markerId.value == 'child_dest');
        if (journey != null) {
          final pts = RoutesService.decodePolyline((journey['polyline'] ?? '').toString());
          if (pts.isNotEmpty) {
            _polylines.add(Polyline(
              polylineId: const PolylineId('child_route'),
              color: TG.teal,
              width: 6,
              points: pts,
            ));
          }
          _markers.add(Marker(
            markerId: const MarkerId('child_dest'),
            position: LatLng((journey['toLat'] as num).toDouble(), (journey['toLng'] as num).toDouble()),
            infoWindow: InfoWindow(title: 'Destination: ${journey['to'] ?? ''}'),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
          ));
        }
      });
    });
  }

  String get _childName => _selectedChildName.isNotEmpty ? _selectedChildName : (_selectedChildEmail ?? '');

  String _seenText() {
    final ms = _childSeenMs;
    if (ms == null) return 'Waiting for location…';
    final ago = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    final when = ago.inMinutes < 1
        ? 'just now'
        : ago.inMinutes < 60
            ? '${ago.inMinutes} min ago'
            : ago.inHours < 24
                ? '${ago.inHours} h ago'
                : '${ago.inDays} d ago';
    final dist = (_currentLocation != null && _childPos != null)
        ? ' · ${formatDistance(haversine(GeoPt(_currentLocation!.latitude, _currentLocation!.longitude), GeoPt(_childPos!.latitude, _childPos!.longitude)))} from you'
        : '';
    return 'Seen $when$dist${_childGpsOk ? '' : ' · GPS off'}';
  }

  /// Top card: who is selected; tap to switch child.
  Widget _buildChildBanner() {
    final email = _selectedChildEmail;
    final name = _childName;
    return Material(
      color: TG.surfaceOf(context),
      borderRadius: BorderRadius.circular(16),
      elevation: 3,
      shadowColor: TG.ink.withValues(alpha: 0.25),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _showConnectedChildrenList,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: TG.softOf(context),
                child: email == null
                    ? Icon(Icons.person_search, color: TG.accentTextOf(context))
                    : Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: TextStyle(fontWeight: FontWeight.w800, color: TG.accentTextOf(context))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(email == null ? 'Select a child to track' : name,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                    if (email != null)
                      Text(_seenText(), style: TextStyle(fontSize: 12.5, color: TG.mutedOf(context))),
                  ],
                ),
              ),
              Icon(Icons.unfold_more, color: TG.mutedOf(context)),
            ],
          ),
        ),
      ),
    );
  }

  /// Bottom sheet-style panel, same look as the child's journey panel.
  Widget _bottomPanel() {
    final email = _selectedChildEmail;
    final muted = TG.mutedOf(context);
    final j = _childJourney;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
      decoration: BoxDecoration(
        color: TG.surfaceOf(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: TG.ink.withValues(alpha: 0.10), blurRadius: 12, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: TG.lineOf(context), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text(j != null ? 'ON A JOURNEY' : 'STATUS',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: muted, letterSpacing: 0.6)),
            Text(
              email == null
                  ? 'No child selected'
                  : j != null
                      ? '${j['from'] ?? ''} → ${j['to'] ?? ''}'
                      : 'Not travelling right now',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            if (j != null && j['durationSeconds'] is num)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Planned ${formatDuration((j['durationSeconds'] as num).toInt())}'
                  '${j['distanceMeters'] is num ? ' · ${formatDistance(j['distanceMeters'] as num)}' : ''}',
                  style: TextStyle(fontSize: 12.5, color: TG.accentTextOf(context), fontWeight: FontWeight.w700),
                ),
              ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: email == null
                      ? null
                      : () => sendCheckinAndShowStatus(context, childEmail: email, childName: _childName),
                  icon: const Icon(Icons.health_and_safety_outlined, size: 18),
                  label: const Text('Check on'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _selectedChildPhone.isEmpty
                      ? null
                      : () => launchUrl(Uri(scheme: 'tel', path: _selectedChildPhone)),
                  icon: const Icon(Icons.call, size: 18),
                  label: const Text('Call'),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            if (!_journeyStarted)
              ElevatedButton.icon(
                onPressed: (_isLoading || email == null) ? null : _startJourney,
                icon: const Icon(Icons.directions),
                label: Text(_isLoading ? 'Finding route…' : 'Navigate to ${_childName.split(' ').first}'),
              )
            else
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: TG.sos, foregroundColor: Colors.white),
                onPressed: _exitNavigation,
                icon: const Icon(Icons.close),
                label: const Text('Stop navigation'),
              ),
          ],
        ),
      ),
    );
  }

  /// 🔁 Refresh map and child data
  Future<void> _refreshMap() async {
    await _fetchCurrentLocation();
    if (_selectedChildEmail != null) {
      _subscribeToChildLive(_selectedChildEmail!);
    }
    CustomSnackbar().showSnackBar(context, "Map refreshed");
  }

  /// 🧭 Exit navigation
  Future<void> _exitNavigation() async {
    await _locationSubscription?.cancel();
    setState(() {
      _journeyStarted = false;
      _polylines.removeWhere((p) => p.polylineId.value == 'route');
    });
    CustomSnackbar().showSnackBar(context, "Navigation ended");
  }

  @override
  Widget build(BuildContext context) {
    final initialPos = _currentLocation ?? const LatLng(20.5937, 78.9629);

    return Scaffold(
      appBar: CustomAppBar(
        title: "Track",
        actions: [
          IconButton(tooltip: 'Switch child', onPressed: _showConnectedChildrenList, icon: const Icon(Icons.person_search)),
          IconButton(tooltip: 'Refresh', onPressed: _refreshMap, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (controller) => _mapController = controller,
            initialCameraPosition: CameraPosition(target: initialPos, zoom: 15),
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: true,
            zoomControlsEnabled: false,
          ),
          Positioned(top: 12, left: 16, right: 16, child: _buildChildBanner()),
          Positioned(left: 0, right: 0, bottom: 0, child: _bottomPanel()),
        ],
      ),
    );
  }
}
