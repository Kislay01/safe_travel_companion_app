// lib/modules/child/views/child_dashboard.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sos_system/common/views/add_emergency_contacts.dart';
import 'package:sos_system/common/views/add_place_sheet.dart';
import 'package:sos_system/common/views/sos_hold_button.dart';
import 'package:sos_system/core/app_theme.dart';
import 'package:sos_system/core/user_paths.dart';
import 'package:sos_system/modules/auth/controllers/shared_preference_data.dart';
import 'package:sos_system/modules/child/views/child_emergency_contact_list.dart';
import 'package:sos_system/modules/child/views/child_notifications_page.dart';
import 'package:sos_system/modules/child/views/movement_history_screen.dart';
import 'package:sos_system/services/alerts_service.dart';
import 'package:sos_system/services/saved_places_service.dart';
import 'package:sos_system/services/voice_sos_service.dart';
import 'package:url_launcher/url_launcher.dart';

/// Traveller home: SOS first, then journeys (with saved places) and guardians.
class ChildDashboard extends StatefulWidget {
  /// Switches the bottom-navigation tab (1 = Journey, 3 = Profile).
  final ValueChanged<int>? onOpenTab;
  const ChildDashboard({super.key, this.onOpenTab});

  @override
  State<ChildDashboard> createState() => _ChildDashboardState();
}

class _Guardian {
  final String name;
  final String mobile;
  final bool primary;
  const _Guardian(this.name, this.mobile, this.primary);
}

class _ChildDashboardState extends State<ChildDashboard> {
  final SharedPreferenceData _prefs = SharedPreferenceData();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isLoading = true;
  bool _isLocationOn = true;
  bool _voiceSosOn = false;
  Timer? _locationCheckTimer;

  StreamSubscription<QuerySnapshot>? _childNotifSub;
  StreamSubscription<QuerySnapshot>? _childRequestSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _contactsSub;
  bool _hasUnreadNotifications = false;
  bool _hasPendingRequests = false;
  List<_Guardian> _guardians = const [];

  Stream<List<SavedPlace>>? _placesStream;
  String _placesFor = '';

  /// Cached so rebuilds don't re-subscribe to Firestore.
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
    _load();
    _checkLocationStatus();
    _locationCheckTimer = Timer.periodic(const Duration(seconds: 5), (_) => _checkLocationStatus());
  }

  @override
  void dispose() {
    _locationCheckTimer?.cancel();
    _childNotifSub?.cancel();
    _childRequestSub?.cancel();
    _contactsSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    await _prefs.getSharedPreferenceData();
    final voice = await VoiceSosService.isEnabledInPrefs();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _voiceSosOn = voice;
    });
    final email = _email;
    if (email.isEmpty) return;
    // Safety net: make sure the check-in listener is running.
    AlertsService.instance.ensureChild(childEmail: email, childName: _prefs.name);
    _listen(email);
  }

  void _listen(String email) {
    final child = _firestore.collection('Child').doc(email);
    _childNotifSub = child.collection('notifications').snapshots().listen((snap) {
      final unread = snap.docs.any((d) {
        final m = d.data();
        return !(m['read'] == true || m['viewed'] == true);
      });
      if (mounted) setState(() => _hasUnreadNotifications = unread);
    }, onError: (_) {});
    _childRequestSub = child
        .collection('requests')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snap) {
      if (mounted) setState(() => _hasPendingRequests = snap.docs.isNotEmpty);
    }, onError: (_) {});
    _contactsSub = UserPaths.child(email).collection('emergency_contacts').snapshots().listen((snap) {
      final list = snap.docs.map((d) {
        final m = d.data();
        final name = (m['name'] ?? '').toString().trim();
        return _Guardian(
          name.isNotEmpty ? name : (m['email'] ?? d.id).toString(),
          (m['mobile'] ?? '').toString().trim(),
          m['isPrimary'] == true,
        );
      }).toList()
        ..sort((a, b) => (b.primary ? 1 : 0) - (a.primary ? 1 : 0));
      if (mounted) setState(() => _guardians = list);
    }, onError: (_) {});
  }

  Future<void> _checkLocationStatus() async {
    final on = await Geolocator.isLocationServiceEnabled();
    if (mounted && on != _isLocationOn) setState(() => _isLocationOn = on);
  }

  Future<void> _markAllChildNotificationsRead() async {
    final email = _email;
    if (email.isEmpty) return;
    try {
      final coll = _firestore.collection('Child').doc(email).collection('notifications');
      final snap = await coll.get();
      final batch = _firestore.batch();
      var any = false;
      for (final d in snap.docs) {
        if (d.data()['read'] != true) {
          batch.update(d.reference, {'read': true});
          any = true;
        }
      }
      if (any) await batch.commit();
      if (mounted) setState(() => _hasUnreadNotifications = false);
    } catch (_) {}
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String get _firstName {
    final n = _prefs.name.trim();
    if (n.isEmpty) return 'Traveller';
    return n.split(' ').first;
  }

  void _openJourney([SavedPlace? place]) {
    if (place != null) SavedPlacesService.pendingDestination.value = place;
    widget.onOpenTab?.call(1);
  }

  Future<void> _callPrimary() async {
    final g = _guardians.firstWhere((g) => g.mobile.isNotEmpty, orElse: () => const _Guardian('', '', false));
    if (g.mobile.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number saved for your guardians yet.')),
      );
      return;
    }
    await launchUrl(Uri(scheme: 'tel', path: g.mobile));
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TG.bgOf(context),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(),
                    const SizedBox(height: 14),
                    _statusPill(),
                    _checkinBanner(),
                    const SizedBox(height: 18),
                    _sos(),
                    const SizedBox(height: 22),
                    _journeyCard(),
                    const SizedBox(height: 14),
                    _guardiansCard(),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const MovementHistoryScreen()),
                        ),
                        icon: const Icon(Icons.history),
                        label: const Text('Journey history'),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _header() {
    final ink = TG.inkOf(context), muted = TG.mutedOf(context);
    final initial = _firstName.isNotEmpty ? _firstName[0].toUpperCase() : 'T';
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
          tooltip: 'Requests and notifications',
          onPressed: () async {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChildNotificationsPage()));
            await _markAllChildNotificationsRead();
          },
          icon: Badge(
            isLabelVisible: _hasUnreadNotifications || _hasPendingRequests,
            backgroundColor: TG.teal,
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
    if (!_isLocationOn) {
      return Material(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: Geolocator.openLocationSettings,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.location_off_outlined, color: TG.warn, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Location is off, so guardians can't see you. Tap to turn it on.",
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF7A3E06)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final n = _guardians.length;
    final text = n == 0
        ? 'Location sharing is on · add a guardian'
        : 'Protected · $n ${n == 1 ? 'guardian' : 'guardians'} watching';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: TG.softOf(context), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Icon(Icons.verified_user_outlined, color: TG.accentTextOf(context), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: TG.accentTextOf(context))),
          ),
        ],
      ),
    );
  }

  /// Red banner while a guardian's "Are you OK?" check-in waits for a reply.
  Widget _checkinBanner() {
    final email = _email;
    if (email.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: UserPaths.child(email).collection('checkins').where('status', isEqualTo: 'pending').snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return const SizedBox.shrink();
        final doc = docs.first;
        final data = doc.data();
        final who = (data['guardianName'] ?? '').toString().isNotEmpty
            ? data['guardianName'].toString()
            : (data['guardianEmail'] ?? 'Your guardian').toString();
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
              const Icon(Icons.health_and_safety, color: TG.sos, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text('$who is checking on you. Are you OK?',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF7A0F1E))),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: TG.sos),
                onPressed: () => AlertsService.instance.answerCheckin(
                  id: doc.id,
                  data: data,
                  childEmail: email,
                  childName: _prefs.name,
                  context: context,
                ),
                child: const Text('Reply'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sos() {
    return Column(
      children: [
        const SosHoldButton(size: 160),
        const SizedBox(height: 10),
        Text(
          _voiceSosOn ? 'or say “help”, “bachao” or “madad”' : 'Turn on voice SOS in Settings for hands-free help',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: TG.mutedOf(context)),
        ),
      ],
    );
  }

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: TG.surfaceOf(context),
          borderRadius: BorderRadius.circular(20),
          boxShadow: TG.isDark(context)
              ? null
              : [BoxShadow(color: TG.ink.withValues(alpha: 0.06), blurRadius: 2, offset: const Offset(0, 1))],
        ),
        child: child,
      );

  Widget _journeyCard() {
    final muted = TG.mutedOf(context);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Start a journey', style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Semantics(
            button: true,
            label: 'Search for a destination',
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _openJourney,
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(color: TG.fieldOf(context), borderRadius: BorderRadius.circular(14)),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 20, color: muted),
                    const SizedBox(width: 10),
                    Text('Where are you going?', style: TextStyle(fontSize: 15, color: muted)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          StreamBuilder<List<SavedPlace>>(
            stream: _places(),
            builder: (context, snap) {
              final places = snap.data ?? const <SavedPlace>[];
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in places)
                    GestureDetector(
                      onLongPress: () => _placeMenu(p),
                      child: ActionChip(
                        avatar: Icon(p.icon, size: 18, color: TG.teal),
                        label: Text(p.title),
                        tooltip: 'Go to ${p.name}. Long-press to remove.',
                        onPressed: () => _openJourney(p),
                      ),
                    ),
                  if (places.length < SavedPlacesService.maxPlaces)
                    ActionChip(
                      avatar: Icon(Icons.add, size: 18, color: muted),
                      label: Text(places.isEmpty ? 'Save Home, College…' : 'Add place'),
                      side: BorderSide(color: TG.lineOf(context), style: BorderStyle.solid),
                      backgroundColor: Colors.transparent,
                      onPressed: () => showAddPlaceSheet(context, email: _email),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _placeMenu(SavedPlace p) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: TG.surfaceOf(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(p.icon, color: TG.teal),
              title: Text(p.title, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(p.address.isNotEmpty ? p.address : p.name),
            ),
            ListTile(
              leading: const Icon(Icons.navigation_outlined),
              title: const Text('Start a journey here'),
              onTap: () => Navigator.pop(ctx, 'go'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_location_alt_outlined),
              title: const Text('Change location'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: TG.sos),
              title: const Text('Remove', style: TextStyle(color: TG.sos)),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'go') _openJourney(p);
    if (action == 'edit') showAddPlaceSheet(context, email: _email, initialLabel: p.label);
    if (action == 'remove') {
      await SavedPlacesService.remove(_email, p.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${p.title} removed')));
      }
    }
  }

  Widget _guardiansCard() {
    final muted = TG.mutedOf(context);
    if (_guardians.isEmpty) {
      return _card(
        child: Row(
          children: [
            Icon(Icons.group_add_outlined, color: TG.teal),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Add a guardian so someone is told when you travel.',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AddEmergencyContacts(isGuardian: false)),
              ),
              child: const Text('Add'),
            ),
          ],
        ),
      );
    }
    final names = _guardians.map((g) => g.name.split(' ').first).toList();
    final title = names.length == 1
        ? names.first
        : names.length == 2
            ? '${names[0]} and ${names[1]}'
            : '${names[0]}, ${names[1]} +${names.length - 2}';
    final primary = _guardians.where((g) => g.primary).map((g) => g.name.split(' ').first).firstOrNull;
    const avatarColors = [Color(0xFFFDE2C8), Color(0xFFDCE4FB), Color(0xFFE6DAF7)];
    const avatarText = [Color(0xFF9A4A0B), Color(0xFF2B47A8), Color(0xFF5B3A9E)];
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChildEmergencyContactList())),
      child: _card(
        child: Row(
          children: [
            SizedBox(
              width: 34.0 + 24 * (_guardians.length.clamp(1, 3) - 1),
              height: 34,
              child: Stack(
                children: [
                  for (var i = 0; i < _guardians.length.clamp(0, 3); i++)
                    Positioned(
                      left: i * 24.0,
                      child: CircleAvatar(
                        radius: 17,
                        backgroundColor: TG.surfaceOf(context),
                        child: CircleAvatar(
                          radius: 15,
                          backgroundColor: avatarColors[i],
                          child: Text(
                            _guardians[i].name.isNotEmpty ? _guardians[i].name[0].toUpperCase() : '?',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: avatarText[i]),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  Text(primary != null ? 'Primary: $primary' : 'Your guardians',
                      style: TextStyle(fontSize: 12, color: muted)),
                ],
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Call primary guardian',
              onPressed: _callPrimary,
              icon: const Icon(Icons.call_outlined),
            ),
          ],
        ),
      ),
    );
  }
}
