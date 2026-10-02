import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
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
          color: Colors.blueAccent,
          width: 6,
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
      final lat = (data['latitude'] as num).toDouble();
      final lng = (data['longitude'] as num).toDouble();
      final childPos = LatLng(lat, lng);

      _markers.removeWhere((m) => m.markerId.value == 'child_live');
      _childLiveMarker = Marker(
        markerId: const MarkerId('child_live'),
        position: childPos,
        infoWindow: InfoWindow(
            title: _selectedChildName.isNotEmpty ? _selectedChildName : _selectedChildEmail),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
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
              color: Colors.orange,
              width: 5,
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

  Widget _buildChildBanner() {
    final email = _selectedChildEmail;
    if (email == null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.person_search, color: Colors.blue),
          title: const Text("Select a child to track"),
          onTap: _showConnectedChildrenList,
        ),
      );
    }
    final name = _selectedChildName.isNotEmpty ? _selectedChildName : email;
    final j = _childJourney;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Icon(j != null ? Icons.navigation : Icons.child_care,
                color: j != null ? Colors.orange : Colors.blue),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    j != null ? 'On a journey: ${j['from'] ?? ''} → ${j['to'] ?? ''}' : 'Not on a journey',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () => sendCheckinAndShowStatus(context, childEmail: email, childName: name),
              icon: const Icon(Icons.health_and_safety_outlined),
              label: const Text("Check on"),
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
        title: "Track Child",
        actions: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 0, 18),
            child: GestureDetector(
              onTap: _showConnectedChildrenList,
              child: const Icon(Icons.person_search, color: Colors.blue),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 18, 18, 18),
            child: GestureDetector(
              onTap: _refreshMap,
              child: const Icon(Icons.refresh, color: Colors.blue),
            ),
          ),
          // Padding(
          //   padding: const EdgeInsets.all(18),
          //   child: GestureDetector(
          //     onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MovementHistoryScreen())),
          //     child: const Icon(Icons.list_alt_outlined, color: Colors.blue),
          //   ),
          // ),
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
            zoomControlsEnabled: true,
          ),
          Positioned(top: 12, left: 12, right: 12, child: _buildChildBanner()),
          if (!_journeyStarted)
            Positioned(
              bottom: 30,
              left: 20,
              right: 20,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _startJourney,
                icon: const Icon(Icons.directions, color: Colors.white,),
                label: Text(_isLoading ? "Loading..." : "Navigate to child", style: const TextStyle(color: Colors.white),),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Colors.blue,
                ),
              ),
            )
          else
            Positioned(
              bottom: 30,
              left: 20,
              right: 20,
              child: ElevatedButton.icon(
                onPressed: _exitNavigation,
                icon: const Icon(Icons.exit_to_app,color: Colors.white,),
                label: const Text("Exit Navigation",style: TextStyle(color: Colors.white),),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Colors.redAccent,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
