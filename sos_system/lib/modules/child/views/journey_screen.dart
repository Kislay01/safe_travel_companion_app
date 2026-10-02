import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart' as location;
import 'package:geocoding/geocoding.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:sos_system/common/views/custom_appbar.dart';
import 'package:sos_system/services/journey_service.dart';
import 'package:sos_system/services/places_service.dart';
import 'package:sos_system/services/routes_service.dart';
import 'package:uuid/uuid.dart';
import 'package:sos_system/modules/child/views/movement_history_screen.dart';

class JourneyScreen extends StatefulWidget {
  const JourneyScreen({super.key});

  @override
  State<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends State<JourneyScreen> {
  final location.Location _location = location.Location();
  GoogleMapController? _mapController;

  LatLng? _currentLocation;
  LatLng? _destination;

  String? _currentAddress;
  String? _currentShort;
  String? _destinationAddress;

  final TextEditingController _searchController = TextEditingController();

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  bool _isLoading = false;
  bool _journeyStarted = false;

  StreamSubscription<location.LocationData>? _locationSubscription;
  StreamSubscription<CompassEvent>? _compassSubscription;

  late BitmapDescriptor _carIcon;
  late FlutterTts _flutterTts;

  List<LatLng> _routePoints = [];
  final List<RouteStep> _routeSteps = [];
  int _currentStepIndex = 0;

  double _deviceHeading = 0.0;
  double _lastLat = 0.0;
  double _lastLng = 0.0;

  // Place suggestions (Places API). One session token per search.
  Timer? _debounce;
  String _sessionToken = const Uuid().v4();
  List<PlaceSuggestion> _suggestions = [];
  bool _suggesting = false;
  bool _endingManually = false;

  @override
  void initState() {
    super.initState();
    JourneyService.instance.active.addListener(_onJourneyChanged);
    _initialize().then((_) => _resumeActiveJourney());
  }

  /// Re-opens a journey that was still active (e.g. after an app restart).
  void _resumeActiveJourney() {
    final j = JourneyService.instance.active.value;
    if (j == null || _journeyStarted || !mounted) return;
    _setDestination(j.destination, j.toName);
    setState(() => _journeyStarted = true);
    _startTracking();
  }

  /// Journey finished elsewhere (arrived, or ended): reset the screen.
  void _onJourneyChanged() {
    if (JourneyService.instance.active.value == null && _journeyStarted && !_endingManually) {
      _resetJourneyUi(message: "You have arrived! Your guardians have been notified.");
    }
  }

  void _resetJourneyUi({String? message}) {
    _locationSubscription?.cancel();
    _locationSubscription = null;
    if (!mounted) return;
    setState(() {
      _journeyStarted = false;
      _isLoading = false;
      _polylines.clear();
      _routeSteps.clear();
      _routePoints = [];
      _currentStepIndex = 0;
      _markers.removeWhere((m) => m.markerId.value == 'destination' || m.markerId.value == 'me');
      _destination = null;
      _destinationAddress = null;
      _searchController.clear();
    });
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _endJourney() async {
    _endingManually = true;
    try {
      await JourneyService.instance.finish(arrived: false);
    } finally {
      _endingManually = false;
    }
    _resetJourneyUi(message: "Journey ended. Your guardians have been notified.");
  }

  void _onSearchChanged(String text) {
    _debounce?.cancel();
    if (text.trim().length < 2) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      setState(() => _suggesting = true);
      final results = await PlacesService.autocomplete(
        text,
        sessionToken: _sessionToken,
        near: _currentLocation,
      );
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        _suggesting = false;
      });
    });
  }

  Future<void> _selectSuggestion(PlaceSuggestion s) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _suggestions = [];
      _searchController.text = s.fullText;
    });
    final details = await PlacesService.details(s.placeId, sessionToken: _sessionToken);
    _sessionToken = const Uuid().v4();
    if (!mounted) return;
    if (details == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't load that place. Try again.")));
      return;
    }
    _setDestination(details.location, s.mainText);
  }

  void _setDestination(LatLng dest, String name) {
    _destination = dest;
    _destinationAddress = name;
    _markers.removeWhere((m) => m.markerId.value == 'destination');
    _markers.add(
      Marker(
        markerId: const MarkerId('destination'),
        position: dest,
        infoWindow: InfoWindow(title: name),
      ),
    );
    if (_currentLocation != null) {
      final bounds = _boundsFromLatLngList([_currentLocation!, dest]);
      _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
    } else {
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(dest, 14));
    }
    if (mounted) setState(() {});
  }

  Future<void> _initialize() async {
    await Future.wait([_loadCarIcon(), _fetchCurrentLocation()]);
    _initTts();
    _listenCompass();
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
    JourneyService.instance.active.removeListener(_onJourneyChanged);
    _debounce?.cancel();
    _searchController.dispose();
    _compassSubscription?.cancel();
    _locationSubscription?.cancel();
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
    if (permission == location.PermissionStatus.denied) {
      permission = await _location.requestPermission();
      if (permission != location.PermissionStatus.granted) return;
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

  Future<void> _searchDestination(String query) async {
    if (query.trim().isEmpty) return;
    if (_suggestions.isNotEmpty) {
      await _selectSuggestion(_suggestions.first);
      return;
    }
    try {
      final locations = await locationFromAddress(query);
      if (!mounted) return;
      if (locations.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("No location found")));
        return;
      }
      final loc = locations.first;
      _setDestination(LatLng(loc.latitude, loc.longitude), query.trim());
    } catch (e) {
      debugPrint("Search error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("No location found")));
      }
    }
  }

  Future<void> _startJourney() async {
    if (_currentLocation == null || _destination == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please set both locations first")),
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

      _polylines.clear();
      _polylines.add(
        Polyline(
          polylineId: const PolylineId("route"),
          color: Colors.blueAccent,
          width: 6,
          points: _routePoints,
        ),
      );

      if (_routePoints.isNotEmpty) {
        final bounds = _boundsFromLatLngList(_routePoints);
        _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
      }

      // Save the journey and alert guardians (journey still works offline).
      try {
        await JourneyService.instance.start(
          fromName: _currentShort ?? "Current location",
          toName: _destinationAddress ?? "Destination",
          from: _currentLocation!,
          to: _destination!,
          route: route,
        );
      } catch (e) {
        debugPrint("Could not save journey: $e");
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
      JourneyService.instance.checkArrival(pos.latitude, pos.longitude);

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

  @override
  Widget build(BuildContext context) {
    final initialPos =
        _currentLocation ?? const LatLng(20.5937, 78.9629); // Default: India

    return Scaffold(
      appBar: CustomAppBar(
        title: "Journey",
        actions: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: GestureDetector(
              onTap:
                  () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const MovementHistoryScreen(),
                    ),
                  ),
              child: const Icon(Icons.list_alt_outlined, color: Colors.blue),
            ),
          ),
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
          if (!_journeyStarted)
            Positioned(top: 16, left: 16, right: 16, child: _buildSearchBar()),
          if (_journeyStarted)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Card(
                child: ListTile(
                  leading: const Icon(Icons.navigation, color: Colors.blue),
                  title: Text("Heading to ${_destinationAddress ?? 'destination'}"),
                  subtitle: const Text("Your guardians can see your live location"),
                ),
              ),
            ),
          if (_journeyStarted)
            Positioned(
              bottom: 30,
              left: 20,
              right: 20,
              child: ElevatedButton.icon(
                onPressed: _endJourney,
                icon: const Icon(Icons.stop_circle_outlined, color: Colors.white),
                label: const Text("End Journey", style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Colors.red,
                ),
              ),
            ),
          if (!_journeyStarted)
            Positioned(
              bottom: 30,
              left: 20,
              right: 20,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _startJourney,
                icon: const Icon(Icons.directions, color: Colors.white,),
                label: Text(_isLoading ? "Loading..." : "Start Journey", style: TextStyle(color: Colors.white),),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Colors.blue,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.search, color: Colors.grey),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.black87),
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: "Search destination...",
                    hintStyle: TextStyle(color: Colors.grey),
                    border: InputBorder.none,
                  ),
                  onChanged: _onSearchChanged,
                  onSubmitted: _searchDestination,
                ),
              ),
              if (_suggesting)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.blue),
                  onPressed: () => _searchDestination(_searchController.text),
                ),
            ],
          ),
        ),
        if (_suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            constraints: const BoxConstraints(maxHeight: 280),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ListView.separated(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: _suggestions.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final sug = _suggestions[i];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.place_outlined, color: Colors.redAccent),
                  title: Text(sug.mainText,
                      style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600)),
                  subtitle: sug.secondaryText.isEmpty
                      ? null
                      : Text(sug.secondaryText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.black54)),
                  onTap: () => _selectSuggestion(sug),
                );
              },
            ),
          ),
      ],
    );
  }
}
