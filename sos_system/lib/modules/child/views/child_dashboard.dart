// lib/modules/child/views/child_dashboard.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sos_system/common/views/add_emergency_contacts.dart';
import 'package:sos_system/common/views/custom_appbar.dart';
import 'package:sos_system/modules/child/views/child_emergency_contact_list.dart';
import 'package:sos_system/modules/auth/controllers/shared_preference_data.dart';
import 'package:sos_system/services/sos_service.dart';
import 'package:sos_system/modules/child/views/child_notifications_page.dart';
import 'package:sos_system/modules/child/views/journey_screen.dart';
import 'package:sos_system/modules/child/views/movement_history_screen.dart';

class ChildDashboard extends StatefulWidget {
  /// Switches the bottom-navigation tab (e.g. 1 = Journey) instead of pushing a new page.
  final ValueChanged<int>? onOpenTab;
  const ChildDashboard({super.key, this.onOpenTab});

  @override
  State<ChildDashboard> createState() => _ChildDashboardState();
}

class _ChildDashboardState extends State<ChildDashboard> with SingleTickerProviderStateMixin {
  final SharedPreferenceData sharedPreferenceData = SharedPreferenceData();
  bool _isLoading = true;
  bool _isLocationOn = false;
  Timer? _locationCheckTimer;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // SOS hold state
  bool _isActivated = false;
  double _pressProgress = 0.0;
  Timer? _holdTimer;
  static const int _holdDurationMs = 3000; // 3 seconds
  static const int _tickMs = 50;

  // Notification listener
  StreamSubscription<QuerySnapshot>? _childNotifSub;
  StreamSubscription<QuerySnapshot>? _childRequestSub;
  bool _hasUnreadNotifications = false;
  bool _hasPendingRequests = false;

  @override
  void initState() {
    super.initState();
    _loadSharedPrefs();
    _checkLocationStatus();
    _startAutoRefresh();
    _startChildNotificationListener(); // start listening for notifications
  }

  @override
  void dispose() {
    _locationCheckTimer?.cancel();
    _holdTimer?.cancel();
    _childNotifSub?.cancel();
    _childRequestSub?.cancel();
    super.dispose();
  }

  // Load user data
  Future<void> _loadSharedPrefs() async {
    await sharedPreferenceData.getSharedPreferenceData();
    setState(() {
      _isLoading = false;
    });
  }

  // Check if location service is on/off
  Future<void> _checkLocationStatus() async {
    bool isServiceEnabled = await Geolocator.isLocationServiceEnabled();
    if (mounted) {
      setState(() {
        _isLocationOn = isServiceEnabled;
      });
    }
  }

  // Automatically refresh every 5 seconds
  void _startAutoRefresh() {
    _locationCheckTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _checkLocationStatus();
    });
  }

  // ------------------- Notification Listener for Child -------------------
  void _startChildNotificationListener() async {
    try {
      final prefs = SharedPreferenceData();
      await prefs.getSharedPreferenceData();
      final fallbackEmail = FirebaseAuth.instance.currentUser?.email ?? '';
      final childId = (prefs.email != null && prefs.email.isNotEmpty) ? prefs.email : fallbackEmail;

      if (childId.isEmpty) return;

      final coll = _firestore.collection('Child').doc(childId).collection('notifications');

      _childNotifSub?.cancel();
      _childNotifSub = coll.snapshots().listen((snap) {
        final hasUnread = snap.docs.any((d) {
          final map = d.data() as Map<String, dynamic>? ?? {};
          return !(map['read'] == true || map['viewed'] == true);
        });

        if (mounted) setState(() => _hasUnreadNotifications = hasUnread);
      }, onError: (e) {
        // optional: handle or log error
        // print('Child notifications stream error: $e');
      });

      // Link requests from guardians waiting for this child's answer.
      _childRequestSub?.cancel();
      _childRequestSub = _firestore
          .collection('Child')
          .doc(childId)
          .collection('requests')
          .where('status', isEqualTo: 'pending')
          .snapshots()
          .listen((snap) {
        if (mounted) setState(() => _hasPendingRequests = snap.docs.isNotEmpty);
      }, onError: (_) {});
    } catch (e) {
      // ignore errors
    }
  }

  Future<void> _markAllChildNotificationsRead() async {
    try {
      final prefs = SharedPreferenceData();
      await prefs.getSharedPreferenceData();
      final fallbackEmail = FirebaseAuth.instance.currentUser?.email ?? '';
      final childId = (prefs.email != null && prefs.email.isNotEmpty) ? prefs.email : fallbackEmail;
      if (childId.isEmpty) return;

      final collRef = _firestore.collection('Child').doc(childId).collection('notifications');
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
      // local state will update via listener; ensure local flag cleared
      if (mounted) setState(() => _hasUnreadNotifications = false);
    } catch (e) {
      // ignore update errors gracefully
    }
  }
  // ------------------------------------------------------------

  // ------------------- SOS Hold & Activation -------------------
  void _startHoldTimer() {
    _holdTimer?.cancel();
    if (mounted) {
      setState(() {
        _pressProgress = 0.0;
      });
    }

    final int ticksNeeded = (_holdDurationMs / _tickMs).round();
    int tickCount = 0;

    _holdTimer = Timer.periodic(const Duration(milliseconds: _tickMs), (timer) {
      tickCount++;
      final progress = (tickCount / ticksNeeded).clamp(0.0, 1.0);
      if (mounted) setState(() => _pressProgress = progress);

      if (progress >= 1.0) {
        timer.cancel();
        _activateSOS();
      }
    });
  }

  void _cancelHoldTimer() {
    _holdTimer?.cancel();
    _holdTimer = null;

    if (!_isActivated) {
      if (mounted) setState(() => _pressProgress = 0.0);
    }
  }

  Future<void> _activateSOS() async {
    if (_isActivated) return;
    if (mounted) {
      setState(() {
        _isActivated = true;
        _pressProgress = 1.0;
      });
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('SOS activated! Alerting your guardians...')),
    );

    final message = await SosService.trigger(source: 'button');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }

    // brief visible activated state, then reset
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    setState(() {
      _isActivated = false;
      _pressProgress = 0.0;
    });
  }

  /// Finds primary contact and attempts direct call on Android.
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final backgroundColor = isDark ? const Color(0xFF121212) : Colors.grey[100];
    final cardColor = Theme.of(context).cardColor;
    final textColor = isDark ? Colors.white : Colors.black;
    final subTextColor = isDark ? Colors.grey[400] : Colors.grey[700];
    final baseSosColor = const Color.fromARGB(255, 216, 7, 28);

    return Scaffold(
      appBar: CustomAppBar(
        title: "TravelGuard",
        actions: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: GestureDetector(
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const ChildNotificationsPage()),
                );
                // mark read after returning from notifications page
                await _markAllChildNotificationsRead();
              },
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(
                    Icons.notifications_active_outlined,
                    color: Color.fromRGBO(0, 123, 255, 1.0),
                  ),
                  if (_hasUnreadNotifications || _hasPendingRequests)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Colors.blueAccent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 1.5),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),

      backgroundColor: backgroundColor,

      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(18),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Welcome Text
                    Text(
                      "Welcome back, ${sharedPreferenceData.name.isNotEmpty ? sharedPreferenceData.name : "User"}",
                      style: GoogleFonts.poppins(
                        fontSize: 25,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Location Sharing Info
                    Container(
                      height: 80,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: cardColor,
                        boxShadow: [
                          if (!isDark)
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.1),
                              blurRadius: 3,
                              offset: const Offset(0, 1),
                            ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: Container(
                              height: 35,
                              width: 35,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isDark ? Colors.blueGrey[800] : Colors.blue[100],
                              ),
                              child: const Icon(
                                Icons.location_on_outlined,
                                color: Color.fromRGBO(0, 123, 255, 1.0),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Location Sharing: ${_isLocationOn ? "On" : "Off"}",
                                style: GoogleFonts.poppins(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _isLocationOn
                                    ? "Your location is monitored"
                                    : "Location access is disabled",
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  color: subTextColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // 🚨 SOS Button - press & hold for 3 seconds with left-to-right fill animation
                    GestureDetector(
                      onLongPressStart: (_) => _startHoldTimer(),
                      onLongPressEnd: (_) => _cancelHoldTimer(),
                      onLongPressCancel: () => _cancelHoldTimer(),
                      child: SizedBox(
                        width: double.infinity,
                        height: 80,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Base button (lighter red)
                            Container(
                              width: double.infinity,
                              height: 80,
                              decoration: BoxDecoration(
                                color: baseSosColor.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: baseSosColor.withOpacity(0.18),
                                    blurRadius: 12,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                            ),

                            // Filling overlay (dark red) that grows from left -> right using widthFactor = _pressProgress
                            Positioned.fill(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: FractionallySizedBox(
                                  widthFactor: _pressProgress, // 0.0 -> 1.0
                                  child: Container(
                                    height: 80,
                                    decoration: BoxDecoration(
                                      color: Colors.red[900],
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // Text / Activated UI on top
                            Center(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: _isActivated
                                    ? Row(
                                        key: const ValueKey('activated'),
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 28),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Activated',
                                            style: GoogleFonts.poppins(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 20,
                                            ),
                                          ),
                                        ],
                                      )
                                    : Text(
                                        'SOS',
                                        key: const ValueKey('idle'),
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 20,
                                          color: Colors.white,
                                        ),
                                      ),
                              ),
                            ),

                            // Optional subtle progress indicator text (percentage) on the right side
                            Positioned(
                              right: 12,
                              child: Text(
                                '${(_pressProgress * 100).round()}%',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: Colors.white.withOpacity(0.9),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Quick Actions Title
                    Text(
                      "Quick Actions",
                      style: GoogleFonts.poppins(
                        fontSize: 23,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),

                    const SizedBox(height: 10),

                    // ✅ Responsive Grid of Quick Actions
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount:
                          MediaQuery.of(context).size.width < 600 ? 2 : 3,
                      crossAxisSpacing: 15,
                      mainAxisSpacing: 20,
                      childAspectRatio: 1,
                      children: [
                        _buildQuickAction(
                          context,
                          icon: Icons.map_outlined,
                          label: "My Journey",
                          onTap: () {
                            if (widget.onOpenTab != null) {
                              widget.onOpenTab!(1);
                            } else {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const JourneyScreen(),
                                ),
                              );
                            }
                          },
                          isDark: isDark,
                        ),
                        _buildQuickAction(
                          context,
                          icon: Icons.people_alt_outlined,
                          label: "Add Emergency Contacts",
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) =>
                                    const AddEmergencyContacts(isGuardian: false),
                              ),
                            );
                          },
                          isDark: isDark,
                        ),
                        _buildQuickAction(
                          context,
                          icon: Icons.add_location_alt_outlined,
                          label: "Movement History",
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => const MovementHistoryScreen(),
                              ),
                            );
                          },
                          isDark: isDark,
                        ),
                        _buildQuickAction(
                          context,
                          icon: Icons.call_outlined,
                          label: "Contact Guardian",
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) =>
                                    const ChildEmergencyContactList(),
                              ),
                            );
                          },
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  // 🔹 Helper Widget for Quick Actions
  Widget _buildQuickAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    final cardColor = Theme.of(context).cardColor;
    final textColor = isDark ? Colors.white : Colors.black;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: cardColor,
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
          ],
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
              child:
                  Icon(icon, color: const Color.fromRGBO(0, 123, 255, 1.0)),
            ),
            const SizedBox(height: 5),
            SizedBox(
              width: 120,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 18,
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
