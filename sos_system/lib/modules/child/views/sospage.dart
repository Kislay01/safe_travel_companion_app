// lib/modules/Child/views/sos_page.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sos_system/common/views/custom_appbar.dart';
import 'package:sos_system/modules/auth/controllers/shared_preference_data.dart';
import 'package:sos_system/services/sos_service.dart';

class SOSPage extends StatefulWidget {
  const SOSPage({super.key});

  @override
  _SOSPageState createState() => _SOSPageState();
}

class _SOSPageState extends State<SOSPage> {
  bool _isActivated = false;
  double _pressProgress = 0.0;
  Timer? _holdTimer;
  static const int _holdDurationMs = 3000; // 3 seconds
  static const int _tickMs = 50;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SharedPreferenceData _prefs = SharedPreferenceData();

  String _childEmail = '';

  @override
  void initState() {
    super.initState();
    _initPrefs();
  }

  Future<void> _initPrefs() async {
    await _prefs.getSharedPreferenceData();
    final fallbackEmail = FirebaseAuth.instance.currentUser?.email ?? '';
    setState(() {
      _childEmail =
          (_prefs.email != null && _prefs.email.isNotEmpty) ? _prefs.email : fallbackEmail;
    });
  }

  void _startHoldTimer() {
    _holdTimer?.cancel();
    setState(() {
      _pressProgress = 0.0;
    });

    final int ticksNeeded = (_holdDurationMs / _tickMs).round();
    int tickCount = 0;

    _holdTimer = Timer.periodic(const Duration(milliseconds: _tickMs), (timer) {
      tickCount++;
      final progress = (tickCount / ticksNeeded).clamp(0.0, 1.0);
      setState(() => _pressProgress = progress);

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
      setState(() => _pressProgress = 0.0);
    }
  }

  Future<void> _activateSOS() async {
    if (_isActivated) return;
    setState(() {
      _isActivated = true;
      _pressProgress = 1.0;
    });

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
  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.grey[400] : Colors.grey[700];
    final sosColor = const Color.fromRGBO(220, 53, 69, 1);

    return Scaffold(
      appBar: const CustomAppBar(title: "SOS"),
      backgroundColor: scaffoldBg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'In case of emergency\nPress and hold for 3 seconds to activate',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 18,
                color: textColor,
              ),
            ),
            const SizedBox(height: 30),
            GestureDetector(
              onLongPressStart: (_) => _startHoldTimer(),
              onLongPressEnd: (_) => _cancelHoldTimer(),
              onLongPressCancel: () => _cancelHoldTimer(),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 170,
                    height: 170,
                    child: CircularProgressIndicator(
                      value: _pressProgress,
                      strokeWidth: 8,
                      valueColor: AlwaysStoppedAnimation<Color>(sosColor),
                      backgroundColor: isDark ? Colors.white10 : Colors.black12,
                    ),
                  ),
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      color: sosColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: sosColor.withOpacity(0.25),
                          blurRadius: 20,
                          spreadRadius: 2,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Center(
                      child: _isActivated
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 40),
                                const SizedBox(height: 6),
                                Text(
                                  'Activated',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                              ],
                            )
                          : Text(
                              'SOS',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Or say "Help me" when Voice SOS is on (Settings)',
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontStyle: FontStyle.italic,
                color: subtitleColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
