// lib/modules/guardian/views/guardian_dashboard.dart
import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart' as location;
import 'package:sos_system/common/views/add_emergency_contacts.dart';
import 'package:sos_system/core/app_theme.dart';
import 'package:sos_system/modules/auth/controllers/shared_preference_data.dart';
import 'package:sos_system/modules/guardian/views/child_movement_history_screen.dart';
import 'package:sos_system/modules/guardian/views/guardian_emergency_contact_list.dart';
import 'package:sos_system/core/user_paths.dart';
import 'package:sos_system/modules/child/views/movement_history_screen.dart';
import 'package:sos_system/services/route_scoring.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:sos_system/modules/guardian/views/checkin_status_dialog.dart';
import 'package:sos_system/modules/guardian/views/guardian_alerts_page.dart';
import 'package:sos_system/modules/guardian/views/track_child_screen.dart';

class GuardianDashboard extends StatefulWidget {
  final String guardianEmail; // pass guardian email when constructing
  /// Switches the bottom-navigation tab (1 = Track Child) instead of pushing a new page.
  final ValueChanged<int>? onOpenTab;
  const GuardianDashboard({super.key, required this.guardianEmail, this.onOpenTab});

  @override
  State<GuardianDashboard> createState() => _GuardianDashboardState();
}

class _GuardianDashboardState extends State<GuardianDashboard> {
  final SharedPreferenceData sharedPreferenceData = SharedPreferenceData();
  GoogleMapController? _mapController;
  LatLng? _currentLocation;
  final location.Location _location = location.Location();
  StreamSubscription<location.LocationData>? _locationSub;
  final Map<String, Marker> _childMarkers = {};
  final Map<String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>
  _liveSubs = {};
  bool _isLoading = true;
  bool _userMovedMap = false;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // notification listener
  StreamSubscription<QuerySnapshot>? _guardianNotifSub;
  StreamSubscription<QuerySnapshot>? _guardianRequestSub;
  bool _hasUnreadNotifications = false;
  bool _hasPendingRequests = false;

  @override
  void initState() {
    super.initState();
    _initLocation();
    _loadConnectedChildrenAndSubscribe(); // works even if location permission is denied
    _loadSharedPrefs();
    // Start guardian notifications listener (guardianEmail is available via widget.guardianEmail)
    _startGuardianNotificationListener();
    // After loading current location we load connected children
  }

  Future<void> _loadSharedPrefs() async {
    await sharedPreferenceData.getSharedPreferenceData();
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _initLocation() async {
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

    final locData = await _location.getLocation();
    if (locData.latitude != null && locData.longitude != null) {
      _currentLocation = LatLng(locData.latitude!, locData.longitude!);
      setState(() {});
    }

    // Listen for live location updates of guardian (not children)
    _locationSub = _location.onLocationChanged.listen((locData) {
      if (locData.latitude != null && locData.longitude != null) {
        _currentLocation = LatLng(locData.latitude!, locData.longitude!);
        if (!_userMovedMap) _fitToAllMarkers();
        setState(() {});
      }
    });

    // Load connected children after we have current location
    await _loadConnectedChildrenAndSubscribe();
  }

  final Map<String, String> _childNames = {};
  final Map<String, String> _childPhones = {};

  /// Live status per child, shown in the "Your children" card.
  final Map<String, LatLng> _childPos = {};
  final Map<String, int> _childSeenMs = {};
  final Map<String, bool> _childGpsOk = {};
  final Map<String, String?> _childJourneyTo = {};
  final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>> _journeySubs = {};

  /// Newest unread urgent alert (SOS, lost contact, "need help" reply).
  QueryDocumentSnapshot<Map<String, dynamic>>? _urgent;

  Future<void> _loadConnectedChildrenAndSubscribe() async {
    final kids = await UserPaths.childrenOf(widget.guardianEmail);
    for (final k in kids) {
      _childNames[k.id] = (k.data()['name'] ?? '').toString();
      _childPhones[k.id] = (k.data()['mobile'] ?? '').toString().trim();
      _subscribeToChildLive(k.id);
      _subscribeToChildJourney(k.id);
    }
    if (mounted) setState(() {});
  }

  String _nameOf(String email) {
    final n = _childNames[email] ?? '';
    return n.isNotEmpty ? n : email.split('@').first;
  }

  /// Lets the guardian pick a child (skips the picker if there is only one).
  Future<String?> _pickChild() async {
    if (_childNames.isEmpty) await _loadConnectedChildrenAndSubscribe();
    if (_childNames.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("No linked children yet. Use Add Child first.")));
      }
      return null;
    }
    if (_childNames.length == 1) return _childNames.keys.first;
    if (!mounted) return null;
    return showModalBottomSheet<String>(
      context: context,
      builder: (_) => ListView(
        shrinkWrap: true,
        children: _childNames.keys
            .map((e) => ListTile(
                  leading: const Icon(Icons.child_care),
                  title: Text(_nameOf(e)),
                  subtitle: Text(e),
                  onTap: () => Navigator.pop(context, e),
                ))
            .toList(),
      ),
    );
  }

  Future<void> _callChild(String email) async {
    final phone = _childPhones[email] ?? '';
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("No phone number saved for ${_nameOf(email)}")));
      return;
    }
    final uri = Uri(scheme: 'tel', path: phone);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Could not open the dialer")));
    }
  }

  Future<void> _checkOnChild([String? email]) async {
    final childEmail = email ?? await _pickChild();
    if (childEmail == null || !mounted) return;
    await sendCheckinAndShowStatus(context, childEmail: childEmail, childName: _nameOf(childEmail));
  }

  void _subscribeToChildLive(String childEmail) {
    if (_liveSubs.containsKey(childEmail)) return;

    final stream =
        FirebaseFirestore.instance
            .collection('Child')
            .doc(childEmail)
            .collection('live_location')
            .doc('current')
            .snapshots();

    final sub = stream.listen((snap) {
      if (!snap.exists) return;
      final data = snap.data();
      if (data == null) return;
      final ts = data['timestamp'];
      if (ts is num) _childSeenMs[childEmail] = ts.toInt();
      _childGpsOk[childEmail] = data['gpsOk'] != false;
      if (data['latitude'] is! num || data['longitude'] is! num) {
        if (mounted) setState(() {});
        return;
      }
      final lat = (data['latitude'] as num).toDouble();
      final lng = (data['longitude'] as num).toDouble();
      final pos = LatLng(lat, lng);
      _childPos[childEmail] = pos;

      final marker = Marker(
        markerId: MarkerId(childEmail),
        position: pos,
        infoWindow: InfoWindow(title: _nameOf(childEmail)),
        onTap: () => _showChildOptions(childEmail),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
      );

      if (!mounted) return;
      setState(() {
        _childMarkers[childEmail] = marker;
      });

      // Optionally fit map to include current location and child's position
      if (!_userMovedMap) _fitToAllMarkers();
    });

    _liveSubs[childEmail] = sub;
  }

  void _subscribeToChildJourney(String childEmail) {
    if (_journeySubs.containsKey(childEmail)) return;
    _journeySubs[childEmail] = UserPaths.child(childEmail)
        .collection('journeys')
        .where('status', isEqualTo: 'active')
        .limit(1)
        .snapshots()
        .listen((snap) {
      final to = snap.docs.isEmpty ? null : (snap.docs.first.data()['to'] ?? 'destination').toString();
      if (mounted) setState(() => _childJourneyTo[childEmail] = to);
    }, onError: (_) {});
  }

  void _showChildOptions(String email) {
    showModalBottomSheet(
      context: context,
      builder: (sheetCtx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.health_and_safety_outlined, color: TG.teal),
            title: Text("Check on ${_nameOf(email)}"),
            subtitle: const Text("Sends an \"Are you OK?\" alert"),
            onTap: () {
              Navigator.pop(sheetCtx);
              _checkOnChild(email);
            },
          ),
          ListTile(
            leading: const Icon(Icons.navigation),
            title: const Text("Track / navigate to child"),
            onTap: () {
              Navigator.pop(sheetCtx);
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => TrackChild(
                  guardianEmail: widget.guardianEmail,
                  initialChildEmail: email,
                ),
              ));
            },
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text("Movement history"),
            onTap: () {
              Navigator.pop(sheetCtx);
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => MovementHistoryScreen(
                  childEmail: email,
                  title: "${_nameOf(email)}'s journeys",
                ),
              ));
            },
          ),
          ListTile(
            leading: const Icon(Icons.call),
            title: Text("Call ${_nameOf(email)}"),
            onTap: () {
              Navigator.pop(sheetCtx);
              _callChild(email);
            },
          ),
        ],
      ),
    );
  }

  void _fitToAllMarkers() {
    if (_mapController == null) return;
    final allPoints = <LatLng>[];

    if (_currentLocation != null) allPoints.add(_currentLocation!);
    allPoints.addAll(_childMarkers.values.map((m) => m.position));

    if (allPoints.isEmpty) return;

    double minLat = allPoints.map((p) => p.latitude).reduce(min);
    double maxLat = allPoints.map((p) => p.latitude).reduce(max);
    double minLng = allPoints.map((p) => p.longitude).reduce(min);
    double maxLng = allPoints.map((p) => p.longitude).reduce(max);

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    try {
      _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
    } catch (_) {
      if (_currentLocation != null)
        _mapController!.animateCamera(
          CameraUpdate.newLatLng(_currentLocation!),
        );
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    if (_currentLocation != null) _fitToAllMarkers();
  }

  void _onCameraMove(CameraPosition position) => _userMovedMap = true;

  @override
  void dispose() {
    _locationSub?.cancel();
    for (var s in _liveSubs.values) {
      s.cancel();
    }
    for (final s in _journeySubs.values) {
      s.cancel();
    }
    _mapController?.dispose();
    _guardianNotifSub?.cancel();
    _guardianRequestSub?.cancel();
    super.dispose();
  }

  // ------------------ Guardian notification listener ------------------
  void _startGuardianNotificationListener() {
    try {
      final guardianEmail = widget.guardianEmail;
      if (guardianEmail.isEmpty) return;

      final coll = _firestore
          .collection('Guardian')
          .doc(guardianEmail)
          .collection('notifications');

      _guardianRequestSub?.cancel();
      _guardianRequestSub = _firestore
          .collection('Guardian')
          .doc(guardianEmail)
          .collection('requests')
          .where('status', isEqualTo: 'pending')
          .snapshots()
          .listen((snap) {
        if (mounted) setState(() => _hasPendingRequests = snap.docs.isNotEmpty);
      }, onError: (_) {});

      _guardianNotifSub?.cancel();
      _guardianNotifSub = coll.snapshots().listen(
        (snap) {
          final hasUnread = snap.docs.any((d) {
            final map = d.data();
            return !(map['read'] == true || map['viewed'] == true);
          });
          QueryDocumentSnapshot<Map<String, dynamic>>? urgent;
          var newest = 0;
          for (final d in snap.docs) {
            final m = d.data();
            if (m['read'] == true || m['viewed'] == true) continue;
            final t = m['type'];
            final isUrgent = t == 'sos' || t == 'lost_contact' || (t == 'checkin_response' && m['status'] == 'help');
            if (!isUrgent) continue;
            final at = m['createdAt'];
            final ms = at is Timestamp ? at.millisecondsSinceEpoch : 0;
            if (urgent == null || ms > newest) {
              urgent = d;
              newest = ms;
            }
          }

          if (mounted) {
            setState(() {
              _hasUnreadNotifications = hasUnread;
              _urgent = urgent;
            });
          }
        },
        onError: (e) {
          // optional: handle/log error
          // print('Guardian notifications stream error: $e');
        },
      );
    } catch (e) {
      // ignore
    }
  }

  Future<void> _markAllGuardianNotificationsRead() async {
    try {
      final guardianEmail = widget.guardianEmail;
      if (guardianEmail.isEmpty) return;

      final collRef = _firestore
          .collection('Guardian')
          .doc(guardianEmail)
          .collection('notifications');
      final snap = await collRef.get();
      if (snap.docs.isEmpty) return;

      final batch = _firestore.batch();
      for (var doc in snap.docs) {
        final data = doc.data();
        if (data['read'] != true) {
          batch.update(doc.reference, {'read': true});
        }
      }
      await batch.commit();
      if (mounted) {
        setState(() {
          _hasUnreadNotifications = false;
          _urgent = null;
        });
      }
    } catch (e) {
      // ignore
    }
  }
  // --------------------------------------------------------------------

  // ------------------------------------------------------------------ UI

  void _openTrack([String? email]) {
    if (email == null && widget.onOpenTab != null) {
      widget.onOpenTab!(1);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TrackChild(guardianEmail: widget.guardianEmail, initialChildEmail: email),
    ));
  }

  Future<void> _openAlerts() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => GuardianAlertsPage(guardianEmail: widget.guardianEmail)),
    );
    await _markAllGuardianNotificationsRead();
  }

  void _addChild() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => AddEmergencyContacts(isGuardian: true)),
      ).then((_) => _loadConnectedChildrenAndSubscribe());

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String get _firstName {
    final n = sharedPreferenceData.name.trim();
    return n.isEmpty ? 'Guardian' : n.split(' ').first;
  }

  /// "On a journey to X", "Seen 3 min ago", "No location yet".
  String _statusOf(String email) {
    final to = _childJourneyTo[email];
    if (to != null) return 'On a journey to $to';
    final ms = _childSeenMs[email];
    if (ms == null) return 'No location shared yet';
    final ago = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    final when = ago.inMinutes < 1
        ? 'just now'
        : ago.inMinutes < 60
            ? '${ago.inMinutes} min ago'
            : ago.inHours < 24
                ? '${ago.inHours} h ago'
                : '${ago.inDays} d ago';
    final gps = _childGpsOk[email] == false ? ' · GPS off' : '';
    final dist = (_currentLocation != null && _childPos[email] != null)
        ? ' · ${formatDistance(haversine(GeoPt(_currentLocation!.latitude, _currentLocation!.longitude), GeoPt(_childPos[email]!.latitude, _childPos[email]!.longitude)))} away'
        : '';
    return 'Seen $when$dist$gps';
  }

  bool _isStale(String email) {
    final ms = _childSeenMs[email];
    if (ms == null) return true;
    return DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms)).inMinutes >= 10;
  }

  @override
  Widget build(BuildContext context) {
    final mapHeight = min(260.0, max(170.0, MediaQuery.of(context).size.height * 0.26));
    return Scaffold(
      backgroundColor: TG.bgOf(context),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadConnectedChildrenAndSubscribe,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _header(),
                      const SizedBox(height: 14),
                      _statusPill(),
                      _urgentBanner(),
                      const SizedBox(height: 16),
                      _mapCard(mapHeight),
                      const SizedBox(height: 14),
                      _childrenCard(),
                      const SizedBox(height: 14),
                      _actionsRow(),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _header() {
    final ink = TG.inkOf(context), muted = TG.mutedOf(context);
    final initial = _firstName[0].toUpperCase();
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_greeting, style: TextStyle(fontSize: 14, color: muted)),
              Text(_firstName, style: GoogleFonts.manrope(fontSize: 24, fontWeight: FontWeight.w800, color: ink)),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Alerts and requests',
          onPressed: _openAlerts,
          icon: Badge(
            isLabelVisible: _hasUnreadNotifications || _hasPendingRequests,
            backgroundColor: _urgent != null ? TG.sos : TG.teal,
            smallSize: 9,
            child: Icon(Icons.notifications_none, color: ink),
          ),
        ),
        const SizedBox(width: 4),
        Semantics(
          button: true,
          label: 'Open profile',
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => widget.onOpenTab?.call(3),
            child: CircleAvatar(
              radius: 24,
              backgroundColor: TG.softOf(context),
              child: Text(initial, style: TextStyle(fontWeight: FontWeight.w800, color: TG.accentTextOf(context))),
            ),
          ),
        ),
      ],
    );
  }

  Widget _statusPill() {
    final n = _childNames.length;
    final travelling = _childJourneyTo.values.where((v) => v != null).length;
    final text = n == 0
        ? 'No children linked yet · add one to start'
        : 'Watching $n ${n == 1 ? 'child' : 'children'}'
            '${travelling > 0 ? ' · $travelling on a journey' : ' · all safe at rest'}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: TG.softOf(context), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Icon(Icons.shield_outlined, color: TG.accentTextOf(context), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: TG.accentTextOf(context))),
          ),
        ],
      ),
    );
  }

  /// Red banner for an unread SOS / lost-contact / "need help" alert.
  Widget _urgentBanner() {
    final d = _urgent;
    if (d == null) return const SizedBox.shrink();
    final m = d.data();
    final childEmail = (m['childEmail'] ?? '').toString();
    final title = (m['title'] ?? 'Emergency alert').toString();
    final body = (m['body'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFDECEE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF2A7B1)),
      ),
      child: Row(
        children: [
          const Icon(Icons.sos, color: TG.sos, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF7A0F1E))),
                if (body.isNotEmpty)
                  Text(body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: Color(0xFF7A0F1E))),
              ],
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: TG.sos),
            onPressed: childEmail.isEmpty ? _openAlerts : () => _openTrack(childEmail),
            child: const Text('Track'),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child, EdgeInsets padding = const EdgeInsets.all(16)}) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: TG.surfaceOf(context),
          borderRadius: BorderRadius.circular(20),
          boxShadow: TG.isDark(context)
              ? null
              : [BoxShadow(color: TG.ink.withValues(alpha: 0.06), blurRadius: 2, offset: const Offset(0, 1))],
        ),
        child: child,
      );

  Widget _mapCard(double height) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            GoogleMap(
              onMapCreated: _onMapCreated,
              initialCameraPosition: CameraPosition(
                target: _currentLocation ?? const LatLng(20.5937, 78.9629),
                zoom: 6.5,
              ),
              markers: _childMarkers.values.toSet(),
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              onCameraMove: _onCameraMove,
            ),
            Positioned(
              right: 10,
              bottom: 10,
              child: Row(
                children: [
                  _mapButton(Icons.center_focus_strong_outlined, 'Show everyone', () {
                    _userMovedMap = false;
                    _fitToAllMarkers();
                  }),
                  const SizedBox(width: 8),
                  _mapButton(Icons.open_in_full, 'Open live tracking', () => _openTrack()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mapButton(IconData icon, String tip, VoidCallback onTap) => Material(
        color: TG.surfaceOf(context),
        shape: const CircleBorder(),
        elevation: 2,
        child: IconButton(tooltip: tip, onPressed: onTap, icon: Icon(icon, color: TG.accentTextOf(context))),
      );

  Widget _childrenCard() {
    final muted = TG.mutedOf(context);
    final kids = _childNames.keys.toList()..sort((a, b) => _nameOf(a).compareTo(_nameOf(b)));
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Your children', style: GoogleFonts.manrope(fontSize: 17, fontWeight: FontWeight.w800)),
              ),
              TextButton.icon(onPressed: _addChild, icon: const Icon(Icons.person_add_alt, size: 18), label: const Text('Add')),
            ],
          ),
          if (kids.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Link a child to see their live location, journeys and alerts here.',
                style: TextStyle(fontSize: 13, color: muted),
              ),
            ),
          for (final e in kids) _childRow(e),
        ],
      ),
    );
  }

  Widget _childRow(String email) {
    final name = _nameOf(email);
    final travelling = _childJourneyTo[email] != null;
    final stale = !travelling && _isStale(email);
    final dot = travelling ? TG.teal : (stale ? TG.warn : const Color(0xFF2E9D5B));
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _showChildOptions(email),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: TG.softOf(context),
                  child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: TextStyle(fontWeight: FontWeight.w800, color: TG.accentTextOf(context))),
                ),
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      color: dot,
                      shape: BoxShape.circle,
                      border: Border.all(color: TG.surfaceOf(context), width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  Text(_statusOf(email),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: travelling ? TG.accentTextOf(context) : TG.mutedOf(context),
                        fontWeight: travelling ? FontWeight.w700 : FontWeight.w500,
                      )),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Check on $name',
              onPressed: () => _checkOnChild(email),
              icon: Icon(Icons.health_and_safety_outlined, color: TG.accentTextOf(context)),
            ),
            IconButton.filledTonal(
              tooltip: 'Call $name',
              onPressed: () => _callChild(email),
              icon: const Icon(Icons.call),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionsRow() {
    final items = <(IconData, String, VoidCallback)>[
      (Icons.near_me_outlined, 'Track live', () => _openTrack()),
      (Icons.health_and_safety_outlined, 'Check on', () => _checkOnChild()),
      (Icons.history, 'History', () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ChildMovementHistory()),
          )),
      (Icons.contacts_outlined, 'Contacts', () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const GuardianEmergencyContactList()),
          )),
    ];
    return _card(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Row(
        children: [
          for (final (icon, label, onTap) in items)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: TG.softOf(context), borderRadius: BorderRadius.circular(14)),
                        child: Icon(icon, color: TG.accentTextOf(context)),
                      ),
                      const SizedBox(height: 6),
                      Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
