import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart' as location;
import 'package:sos_system/common/views/add_place_sheet.dart';
import 'package:sos_system/common/views/custom_appbar.dart';
import 'package:sos_system/common/views/sos_hold_button.dart';
import 'package:sos_system/core/app_theme.dart';
import 'package:sos_system/core/user_paths.dart';
import 'package:sos_system/modules/auth/controllers/shared_preference_data.dart';
import 'package:sos_system/modules/child/views/movement_history_screen.dart';
import 'package:sos_system/services/busier_route_service.dart';
import 'package:sos_system/services/journey_service.dart';
import 'package:sos_system/services/location_sharing_service.dart';
import 'package:sos_system/services/places_service.dart';
import 'package:sos_system/services/route_scoring.dart';
import 'package:sos_system/services/routes_service.dart';
import 'package:sos_system/services/saved_places_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

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

  /// The route currently drawn; a different one from JourneyService means a re-route.
  RouteResult? _shownRoute;

  // Route options (busier-route suggestion) before starting.
  BusierRouteResult? _options;
  int _selected = 0;
  bool _loadingOptions = false;
  String? _optionsError;

  // Progress while travelling.
  double _remainingMeters = 0;

  final SharedPreferenceData _prefs = SharedPreferenceData();
  String _guardianName = '';
  String _guardianPhone = '';

  Stream<List<SavedPlace>>? _placesStream;
  String _placesFor = '';

  Stream<List<SavedPlace>> _places() {
    final e = _email;
    if (e.isEmpty) return Stream.value(const <SavedPlace>[]);
    if (_placesStream == null || _placesFor != e) {
      _placesFor = e;
      _placesStream = SavedPlacesService.watch(e);
    }
    return _placesStream!;
  }

  String get _email => _prefs.email.isNotEmpty ? _prefs.email : (FirebaseAuth.instance.currentUser?.email ?? '');

  @override
  void initState() {
    super.initState();
    JourneyService.instance.active.addListener(_onJourneyChanged);
    JourneyService.instance.route.addListener(_onRouteChanged);
    SavedPlacesService.pendingDestination.addListener(_onPendingPlace);
    _initialize().then((_) {
      _resumeActiveJourney();
      _onPendingPlace();
    });
    _loadGuardian();
  }

  Future<void> _loadGuardian() async {
    await _prefs.getSharedPreferenceData();
    if (mounted) setState(() {}); // email is known now: saved places can load
    final email = _email;
    if (email.isEmpty) return;
    try {
      final contacts = UserPaths.child(email).collection('emergency_contacts');
      var q = await contacts.where('isPrimary', isEqualTo: true).limit(1).get();
      if (q.docs.isEmpty) q = await contacts.limit(1).get();
      if (q.docs.isEmpty || !mounted) return;
      final m = q.docs.first.data();
      setState(() {
        _guardianName = (m['name'] ?? '').toString().trim().split(' ').first;
        _guardianPhone = (m['mobile'] ?? '').toString().trim();
      });
    } catch (_) {}
  }

  /// A saved place was tapped on Home: make it the destination.
  void _onPendingPlace() {
    final p = SavedPlacesService.pendingDestination.value;
    if (p == null || !mounted) return;
    SavedPlacesService.pendingDestination.value = null;
    if (_journeyStarted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End the current journey before starting a new one.')),
      );
      return;
    }
    _searchController.text = p.title;
    _setDestination(p.location, p.title == p.name ? p.name : '${p.title} (${p.name})');
  }

  /// Re-opens a journey that was still active (e.g. after an app restart).
  void _resumeActiveJourney() {
    final j = JourneyService.instance.active.value;
    if (j == null || _journeyStarted || !mounted) return;
    _setDestination(j.destination, j.toName, loadOptions: false);
    setState(() => _journeyStarted = true);
    _onRouteChanged(); // draw the saved route after an app restart
    _startTracking();
  }

  /// The traveller left the planned route and a new one was computed:
  /// redraw it and restart voice guidance, like Google Maps re-routing.
  void _onRouteChanged() {
    final r = JourneyService.instance.route.value;
    if (!_journeyStarted || r == null || identical(r, _shownRoute) || !mounted) return;
    final firstDraw = _shownRoute == null;
    _shownRoute = r;
    setState(() {
      _routePoints = r.points;
      _remainingMeters = r.distanceMeters.toDouble();
      _polylines
        ..clear()
        ..add(_line('route', _routePoints, selected: true));
      if (r.steps.isNotEmpty) {
        _routeSteps
          ..clear()
          ..addAll(r.steps);
        _currentStepIndex = 0;
      }
    });
    if (!firstDraw) {
      _flutterTts.speak(r.steps.isNotEmpty ? "Route updated. ${r.steps.first.instruction}" : "Route updated");
    }
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
      _shownRoute = null;
      _options = null;
      _optionsError = null;
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

  void _clearDestination() {
    setState(() {
      _destination = null;
      _destinationAddress = null;
      _options = null;
      _optionsError = null;
      _polylines.clear();
      _markers.removeWhere((m) => m.markerId.value == 'destination');
      _searchController.clear();
    });
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
      final results = await PlacesService.autocomplete(text, sessionToken: _sessionToken, near: _currentLocation);
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't load that place. Try again.")));
      return;
    }
    _setDestination(details.location, s.mainText);
  }

  void _setDestination(LatLng dest, String name, {bool loadOptions = true}) {
    _destination = dest;
    _destinationAddress = name;
    _markers.removeWhere((m) => m.markerId.value == 'destination');
    _markers.add(Marker(markerId: const MarkerId('destination'), position: dest, infoWindow: InfoWindow(title: name)));
    if (_currentLocation != null) {
      _mapController?.animateCamera(
          CameraUpdate.newLatLngBounds(_boundsFromLatLngList([_currentLocation!, dest]), 80));
    } else {
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(dest, 14));
    }
    if (mounted) setState(() {});
    if (loadOptions) _loadRouteOptions();
  }

  /// Fetches alternatives and marks the fastest and the busier one.
  Future<void> _loadRouteOptions() async {
    if (_currentLocation == null || _destination == null) return;
    setState(() {
      _loadingOptions = true;
      _optionsError = null;
      _options = null;
    });
    try {
      final result = await BusierRouteService.compare(origin: _currentLocation!, destination: _destination!);
      if (!mounted || _journeyStarted) return;
      setState(() {
        _options = result;
        _selected = 0; // recommended first
        _loadingOptions = false;
      });
      _drawOptions();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingOptions = false;
        _optionsError = e is RoutesException ? e.message : "Couldn't compare routes. You can still start.";
      });
    }
  }

  Polyline _line(String id, List<LatLng> pts, {required bool selected, VoidCallback? onTap}) => Polyline(
        polylineId: PolylineId(id),
        points: pts,
        color: selected ? TG.teal : const Color(0xFF9DB0AB),
        width: selected ? 7 : 5,
        zIndex: selected ? 2 : 1,
        consumeTapEvents: onTap != null,
        onTap: onTap,
      );

  void _drawOptions() {
    final o = _options;
    if (o == null) return;
    setState(() {
      _polylines
        ..clear()
        ..addAll([
          for (var i = 0; i < o.options.length; i++)
            _line('opt$i', o.options[i].route.points,
                selected: i == _selected, onTap: () => _selectOption(i)),
        ]);
    });
    final pts = o.options[_selected].route.points;
    if (pts.isNotEmpty) {
      _mapController?.animateCamera(CameraUpdate.newLatLngBounds(_boundsFromLatLngList(pts), 70));
    }
  }

  void _selectOption(int i) {
    setState(() => _selected = i);
    _drawOptions();
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
      if (event.heading != null) _deviceHeading = event.heading!;
    });
  }

  @override
  void dispose() {
    JourneyService.instance.active.removeListener(_onJourneyChanged);
    JourneyService.instance.route.removeListener(_onRouteChanged);
    SavedPlacesService.pendingDestination.removeListener(_onPendingPlace);
    _debounce?.cancel();
    _searchController.dispose();
    _compassSubscription?.cancel();
    _locationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadCarIcon() async {
    try {
      _carIcon = await BitmapDescriptor.asset(
        const ImageConfiguration(size: Size(48, 48)),
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
      final placemarks = await placemarkFromCoordinates(loc.latitude!, loc.longitude!);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        _currentShort = "${p.subLocality ?? p.name ?? ""}, ${p.locality ?? p.administrativeArea ?? ""}";
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No location found")));
        return;
      }
      _setDestination(LatLng(locations.first.latitude, locations.first.longitude), query.trim());
    } catch (e) {
      debugPrint("Search error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No location found")));
      }
    }
  }

  Future<void> _startJourney() async {
    if (_currentLocation == null || _destination == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please set a destination first")));
      return;
    }
    setState(() => _isLoading = true);

    try {
      // Use the route the traveller picked; fall back to a single route.
      final picked = _options?.options[_selected].route;
      final route = picked ?? await RoutesService.computeRoute(origin: _currentLocation!, destination: _destination!);

      setState(() {
        _journeyStarted = true;
        _options = null;
        _shownRoute = route;
        _routePoints = route.points;
        _remainingMeters = route.distanceMeters.toDouble();
        _routeSteps
          ..clear()
          ..addAll(route.steps);
        _currentStepIndex = 0;
        _polylines
          ..clear()
          ..add(_line('route', _routePoints, selected: true));
      });
      if (_routeSteps.isNotEmpty) _flutterTts.speak(_routeSteps.first.instruction);
      if (_routePoints.isNotEmpty) {
        _mapController?.animateCamera(CameraUpdate.newLatLngBounds(_boundsFromLatLngList(_routePoints), 80));
      }

      // Save the journey and alert guardians (navigation still works offline).
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
        setState(() => _journeyStarted = false);
      }
    } catch (e) {
      debugPrint("Error fetching route: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not get a route. Try again.")));
        setState(() => _journeyStarted = false);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _startTracking() {
    _location.changeSettings(interval: 1000, distanceFilter: 2);
    _locationSubscription?.cancel();
    _locationSubscription = _location.onLocationChanged.listen((loc) {
      if (loc.latitude == null || loc.longitude == null) return;
      final pos = LatLng(loc.latitude!, loc.longitude!);

      if (_lastLat != 0 && _lastLng != 0) {
        if (_distanceBetween(pos, LatLng(_lastLat, _lastLng)) < 3) return;
      }
      _lastLat = pos.latitude;
      _lastLng = pos.longitude;

      _markers.removeWhere((m) => m.markerId.value == 'me');
      _markers.add(Marker(
        markerId: const MarkerId('me'),
        position: pos,
        rotation: _deviceHeading,
        icon: _carIcon,
        anchor: const Offset(0.5, 0.5),
      ));
      _currentLocation = pos;
      if (_routePoints.isNotEmpty) {
        _remainingMeters = remainingMeters(
          _routePoints.map((p) => GeoPt(p.latitude, p.longitude)).toList(),
          GeoPt(pos.latitude, pos.longitude),
        );
      }

      _showNextInstruction(pos);
      // Shares the live position with guardians and lets the journey
      // service detect arrival or re-route when off the planned path.
      LocationSharingService.instance.reportPosition(pos.latitude, pos.longitude);

      _mapController?.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(target: pos, zoom: 17, tilt: 65, bearing: _deviceHeading),
      ));
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
      if (mounted) setState(() {});
    }
  }

  double _distanceBetween(LatLng a, LatLng b) =>
      haversine(GeoPt(a.latitude, a.longitude), GeoPt(b.latitude, b.longitude));

  LatLngBounds _boundsFromLatLngList(List<LatLng> list) {
    double minLat = list.first.latitude, maxLat = list.first.latitude;
    double minLng = list.first.longitude, maxLng = list.first.longitude;
    for (final p in list) {
      minLat = min(minLat, p.latitude);
      maxLat = max(maxLat, p.latitude);
      minLng = min(minLng, p.longitude);
      maxLng = max(maxLng, p.longitude);
    }
    return LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng));
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final initialPos = _currentLocation ?? const LatLng(20.5937, 78.9629); // Default: India
    return Scaffold(
      appBar: CustomAppBar(
        title: "Journey",
        actions: [
          IconButton(
            tooltip: 'Journey history',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MovementHistoryScreen())),
            icon: const Icon(Icons.history),
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
            myLocationButtonEnabled: !_journeyStarted,
            zoomControlsEnabled: false,
          ),
          if (!_journeyStarted) Positioned(top: 12, left: 16, right: 16, child: _buildSearchBar()),
          if (_journeyStarted) Positioned(top: 12, left: 16, right: 16, child: _instructionBanner()),
          if (_journeyStarted)
            const Positioned(
              right: 18,
              bottom: 252,
              child: SosHoldButton(size: 76, showRings: false, hint: ''),
            ),
          Positioned(left: 0, right: 0, bottom: 0, child: _bottomPanel()),
        ],
      ),
    );
  }

  Widget _panel({required List<Widget> children}) => Container(
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
              ...children,
            ],
          ),
        ),
      );

  Widget _bottomPanel() {
    if (_journeyStarted) return _activePanel();
    if (_destination == null) return const SizedBox.shrink();
    return _optionsPanel();
  }

  Widget _optionsPanel() {
    final muted = TG.mutedOf(context);
    final o = _options;
    return _panel(children: [
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('GOING TO', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: muted, letterSpacing: 0.6)),
                Text(_destinationAddress ?? 'Destination',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(fontSize: 19, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          IconButton(tooltip: 'Clear destination', onPressed: _clearDestination, icon: const Icon(Icons.close)),
        ],
      ),
      const SizedBox(height: 10),
      if (_loadingOptions)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 12),
            Text('Comparing routes…', style: TextStyle(color: muted)),
          ]),
        ),
      if (_optionsError != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(_optionsError!, style: TextStyle(color: muted)),
        ),
      if (o != null) ...[
        if (o.night && o.options.any((x) => x.score.busier))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('It’s late: we suggest the busier route, with more open places along the way.',
                style: TextStyle(fontSize: 13, color: TG.accentTextOf(context), fontWeight: FontWeight.w600)),
          ),
        if (o.options.length == 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Only one route found for this trip.', style: TextStyle(fontSize: 13, color: muted)),
          ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 210),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: o.options.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _optionTile(o.options[i], i),
          ),
        ),
        if (!o.busynessChecked)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text("Couldn't check how busy the roads are right now.", style: TextStyle(fontSize: 12, color: muted)),
          ),
      ],
      const SizedBox(height: 12),
      ElevatedButton.icon(
        onPressed: _isLoading || _loadingOptions ? null : _startJourney,
        icon: const Icon(Icons.navigation_outlined),
        label: Text(_isLoading ? 'Starting…' : 'Start journey'),
      ),
    ]);
  }

  Widget _optionTile(RouteOption opt, int i) {
    final sel = i == _selected;
    final badgeColor = opt.score.busier ? TG.teal : TG.mutedOf(context);
    return Material(
      color: sel ? TG.softOf(context) : TG.fieldOf(context),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _selectOption(i),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: sel ? TG.teal : Colors.transparent, width: 1.5),
          ),
          child: Row(
            children: [
              Icon(sel ? Icons.radio_button_checked : Icons.radio_button_off, color: sel ? TG.teal : TG.mutedOf(context)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(opt.badge, style: TextStyle(fontWeight: FontWeight.w800, color: badgeColor)),
                      if (opt.score.recommended && (_options?.options.length ?? 0) > 1) ...[
                        const SizedBox(width: 6),
                        Text('· suggested', style: TextStyle(fontSize: 12, color: TG.mutedOf(context))),
                      ],
                    ]),
                    const SizedBox(height: 2),
                    Text(opt.detail, style: TextStyle(fontSize: 12.5, color: TG.mutedOf(context))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _activePanel() {
    final muted = TG.mutedOf(context);
    final route = _shownRoute;
    final total = (route?.distanceMeters ?? 0).toDouble();
    final remaining = _remainingMeters.clamp(0, total > 0 ? total : _remainingMeters).toDouble();
    final fraction = total > 0 ? (1 - remaining / total).clamp(0.0, 1.0) : 0.0;
    final etaSec = (route == null || total <= 0) ? 0 : (route.durationSeconds * (remaining / total)).round();
    final arrive = DateTime.now().add(Duration(seconds: etaSec));
    final arriveText = TimeOfDay.fromDateTime(arrive).format(context);
    final who = _guardianName.isNotEmpty ? _guardianName : 'Your guardians';

    return _panel(children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('HEADING TO', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: muted, letterSpacing: 0.6)),
                Text(_destinationAddress ?? 'Destination',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(fontSize: 20, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(route == null ? '—' : formatDuration(etaSec),
                  style: GoogleFonts.manrope(fontSize: 20, fontWeight: FontWeight.w800, color: TG.accentTextOf(context))),
              Text(route == null ? '' : '${formatDistance(remaining)} · arrive $arriveText',
                  style: TextStyle(fontSize: 12, color: muted)),
            ],
          ),
        ],
      ),
      const SizedBox(height: 12),
      ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: fraction,
          minHeight: 6,
          color: TG.teal,
          backgroundColor: TG.lineOf(context),
        ),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: TG.fieldOf(context), borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Icon(Icons.verified_user_outlined, size: 18, color: TG.teal),
          const SizedBox(width: 10),
          Expanded(
            child: Text('$who can see you. They’ll be told when you arrive.', style: const TextStyle(fontSize: 13)),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: _endJourney, child: const Text('End journey'))),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton(
            onPressed: _guardianPhone.isEmpty ? null : () => launchUrl(Uri(scheme: 'tel', path: _guardianPhone)),
            child: Text(_guardianName.isNotEmpty ? 'Call $_guardianName' : 'Call guardian'),
          ),
        ),
      ]),
    ]);
  }

  Widget _instructionBanner() {
    final hasStep = _currentStepIndex < _routeSteps.length;
    final text = hasStep ? _routeSteps[_currentStepIndex].instruction : 'Heading to ${_destinationAddress ?? 'destination'}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: TG.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: TG.ink.withValues(alpha: 0.12), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: TG.softOf(context), borderRadius: BorderRadius.circular(12)),
          child: Icon(Icons.turn_slight_left, color: TG.accentTextOf(context)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  Widget _buildSearchBar() {
    final muted = TG.mutedOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: TG.surfaceOf(context),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: TG.ink.withValues(alpha: 0.10), blurRadius: 8, offset: const Offset(0, 3))],
          ),
          child: Row(
            children: [
              Icon(Icons.search, color: muted),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: "Where are you going?",
                    filled: false,
                    border: InputBorder.none,
                  ),
                  onChanged: _onSearchChanged,
                  onSubmitted: _searchDestination,
                ),
              ),
              if (_suggesting)
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              else
                IconButton(
                  tooltip: 'Search',
                  icon: Icon(Icons.arrow_forward, color: TG.teal),
                  onPressed: () => _searchDestination(_searchController.text),
                ),
            ],
          ),
        ),
        if (_suggestions.isEmpty && _destination == null) _savedPlacesRow(),
        if (_suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            constraints: const BoxConstraints(maxHeight: 280),
            decoration: BoxDecoration(
              color: TG.surfaceOf(context),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: TG.ink.withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0, 3))],
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
                  leading: Icon(Icons.place_outlined, color: TG.teal),
                  title: Text(sug.mainText, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: sug.secondaryText.isEmpty
                      ? null
                      : Text(sug.secondaryText, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => _selectSuggestion(sug),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _savedPlacesRow() {
    return StreamBuilder<List<SavedPlace>>(
      stream: _places(),
      builder: (context, snap) {
        final places = snap.data ?? const <SavedPlace>[];
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final p in places)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      avatar: Icon(p.icon, size: 18, color: TG.teal),
                      label: Text(p.title),
                      onPressed: () {
                        _searchController.text = p.title;
                        _setDestination(p.location, p.title == p.name ? p.name : '${p.title} (${p.name})');
                      },
                    ),
                  ),
                if (places.length < SavedPlacesService.maxPlaces)
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: Text(places.isEmpty ? 'Save a place' : 'Add'),
                    onPressed: _email.isEmpty ? null : () => showAddPlaceSheet(context, email: _email),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
