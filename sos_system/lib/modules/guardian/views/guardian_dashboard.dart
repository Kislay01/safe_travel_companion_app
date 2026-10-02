// lib/modules/guardian/views/guardian_dashboard.dart
import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart' as location;
import 'package:sos_system/common/views/add_emergency_contacts.dart';
import 'package:sos_system/common/views/custom_appbar.dart';
import 'package:sos_system/modules/auth/controllers/shared_preference_data.dart';
import 'package:sos_system/modules/guardian/views/child_movement_history_screen.dart';
import 'package:sos_system/modules/guardian/views/guardian_emergency_contact_list.dart';
import 'package:sos_system/core/user_paths.dart';
import 'package:sos_system/modules/guardian/views/checkin_status_dialog.dart';
import 'package:sos_system/modules/guardian/views/guardian_alerts_page.dart';
import 'package:sos_system/modules/guardian/views/track_child_screen.dart';

class GuardianDashboard extends StatefulWidget {
  final String guardianEmail; // pass guardian email when constructing
  const GuardianDashboard({super.key, required this.guardianEmail});

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
  bool _hasUnreadNotifications = false;

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

  Future<void> _loadConnectedChildrenAndSubscribe() async {
    final kids = await UserPaths.childrenOf(widget.guardianEmail);
    for (final k in kids) {
      _childNames[k.id] = (k.data()['name'] ?? '').toString();
      _subscribeToChildLive(k.id);
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
      final lat = (data['latitude'] as num).toDouble();
      final lng = (data['longitude'] as num).toDouble();
      final pos = LatLng(lat, lng);

      final marker = Marker(
        markerId: MarkerId(childEmail),
        position: pos,
        infoWindow: InfoWindow(title: _nameOf(childEmail)),
        onTap: () => _showChildOptions(childEmail),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      );

      setState(() {
        _childMarkers[childEmail] = marker;
      });

      // Optionally fit map to include current location and child's position
      if (!_userMovedMap) _fitToAllMarkers();
    });

    _liveSubs[childEmail] = sub;
  }

  void _showChildOptions(String email) {
    showModalBottomSheet(
      context: context,
      builder: (sheetCtx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.health_and_safety_outlined, color: Colors.orange),
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
                builder: (_) => const ChildMovementHistory(),
              ));
            },
          ),
          ListTile(
            leading: const Icon(Icons.call),
            title: const Text("Call child"),
            onTap: () {
              Navigator.pop(sheetCtx);
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const GuardianEmergencyContactList(),
              ));
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
    _mapController?.dispose();
    _guardianNotifSub?.cancel();
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

      _guardianNotifSub?.cancel();
      _guardianNotifSub = coll.snapshots().listen(
        (snap) {
          final hasUnread = snap.docs.any((d) {
            final map = d.data() as Map<String, dynamic>? ?? {};
            return !(map['read'] == true || map['viewed'] == true);
          });

          if (mounted) setState(() => _hasUnreadNotifications = hasUnread);
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
        final data = doc.data() as Map<String, dynamic>? ?? {};
        if (data['read'] != true) {
          batch.update(doc.reference, {'read': true});
        }
      }
      await batch.commit();
      if (mounted) setState(() => _hasUnreadNotifications = false);
    } catch (e) {
      // ignore
    }
  }
  // --------------------------------------------------------------------

  List<_QuickActionItem> get _actions => [
    _QuickActionItem(
      icon: Icons.map_outlined,
      label: "Track Child",
      onTap:
          (ctx) => Navigator.of(ctx).push(
            MaterialPageRoute(
              builder: (_) => TrackChild(guardianEmail: widget.guardianEmail),
            ),
          ),
    ),
    _QuickActionItem(
      icon: Icons.person_add,
      label: "Add Child",
      onTap:
          (ctx) => Navigator.of(ctx).push(
            MaterialPageRoute(
              builder: (_) => AddEmergencyContacts(isGuardian: true),
            ),
          ),
    ),
    _QuickActionItem(
      icon: Icons.add_location_alt_outlined,
      label: "Child Movement",
      onTap:
          (ctx) => Navigator.of(ctx).push(
            MaterialPageRoute(builder: (_) => const ChildMovementHistory()),
          ),
    ),
    _QuickActionItem(
      icon: Icons.health_and_safety_outlined,
      label: "Check on Child",
      onTap: (ctx) => _checkOnChild(),
    ),
    _QuickActionItem(
      icon: Icons.call_outlined,
      label: "Contact Child",
      onTap:
          (ctx) => Navigator.of(ctx).push(
            MaterialPageRoute(
              builder: (_) => const GuardianEmergencyContactList(),
            ),
          ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF5F7FA);
    final cardColor = Theme.of(context).cardColor;
    final textColor = isDark ? Colors.white : Colors.black;
    final subColor = isDark ? Colors.grey[400] : Colors.grey[700];

    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final screenHeight = media.size.height;
    final double mapHeight = min(320, max(160, screenHeight * 0.30));
    final int crossAxisCount = screenWidth < 500 ? 2 : 3;
    final double childAspectRatio = screenWidth < 400 ? 1.05 : 1.12;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: CustomAppBar(
        title: "TravelGuard",
        actions: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: GestureDetector(
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GuardianAlertsPage(guardianEmail: widget.guardianEmail),
                  ),
                );
                // mark all read after returning from notifications page
                await _markAllGuardianNotificationsRead();
              },
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(
                    Icons.notifications_active_outlined,
                    color: Color.fromRGBO(0, 123, 255, 1.0),
                  ),
                  if (_hasUnreadNotifications) 
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Colors.blueAccent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SafeArea(
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                        child: Text(
                          "Welcome back, ${sharedPreferenceData.name.isNotEmpty ? sharedPreferenceData.name : "User"}",
                          style: GoogleFonts.poppins(
                            fontSize: 25,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              if (!isDark)
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                            ],
                            border: Border.all(
                              color:
                                  isDark
                                      ? Colors.grey[800]!
                                      : Colors.transparent,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: SizedBox(
                              height: mapHeight,
                              child: GoogleMap(
                                onMapCreated: _onMapCreated,
                                initialCameraPosition: CameraPosition(
                                  target:
                                      _currentLocation ??
                                      const LatLng(20.5937, 78.9629),
                                  zoom: 6.5,
                                ),
                                markers: _childMarkers.values.toSet(),
                                myLocationEnabled: true,
                                zoomControlsEnabled: true,
                                onCameraMove: _onCameraMove,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 20)),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18.0),
                        child: Text(
                          "Quick Actions",
                          style: GoogleFonts.poppins(
                            fontSize: 23,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 10)),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        18,
                        0,
                        18,
                        media.viewPadding.bottom + 16,
                      ),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: 15,
                          mainAxisSpacing: 20,
                          childAspectRatio: childAspectRatio,
                        ),
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final item = _actions[index];
                          return _buildQuickAction(
                            icon: item.icon,
                            label: item.label,
                            onTap: () => item.onTap(context),
                            isDark: isDark,
                            cardColor: cardColor,
                            textColor: textColor,
                          );
                        }, childCount: _actions.length),
                      ),
                    ),
                  ],
                ),
              ),
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isDark,
    required Color cardColor,
    required Color textColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: cardColor,
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
          ],
          border: Border.all(
            color: isDark ? Colors.grey[800]! : Colors.transparent,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              height: 45,
              width: 45,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark ? Colors.blueGrey[800] : Colors.blue[100],
              ),
              child: Icon(icon, color: const Color.fromRGBO(0, 123, 255, 1.0)),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6.0),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionItem {
  final IconData icon;
  final String label;
  final void Function(BuildContext) onTap;
  _QuickActionItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}
