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
  const ChildDashboard({super.key});

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
  bool _hasUnreadNotifications = false;

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
