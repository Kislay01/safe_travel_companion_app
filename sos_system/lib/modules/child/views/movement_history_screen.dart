import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sos_system/common/views/custom_appbar.dart';
import 'package:sos_system/core/user_paths.dart';
import 'package:sos_system/modules/auth/controllers/shared_preference_data.dart';

/// Journey history for a child. Without [childEmail] it shows the logged-in child's own trips.
class MovementHistoryScreen extends StatefulWidget {
  final String? childEmail;
  final String? title;
  const MovementHistoryScreen({super.key, this.childEmail, this.title});

  @override
  State<MovementHistoryScreen> createState() => _MovementHistoryScreenState();
}

class _MovementHistoryScreenState extends State<MovementHistoryScreen> {
  String? _email;

  @override
  void initState() {
    super.initState();
    _resolveEmail();
  }

  Future<void> _resolveEmail() async {
    var e = widget.childEmail;
    if (e == null || e.isEmpty) {
      final prefs = SharedPreferenceData();
      await prefs.getSharedPreferenceData();
      e = prefs.email;
    }
    if (mounted) setState(() => _email = UserPaths.normalize(e ?? ''));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(title: widget.title ?? "Movement History"),
      body: _email == null
          ? const Center(child: CircularProgressIndicator())
          : JourneyHistoryList(childEmail: _email!),
    );
  }
}

/// Live list of a child's journeys (newest first).
class JourneyHistoryList extends StatelessWidget {
  final String childEmail;
  final int limit;
  final bool shrinkWrap;
  const JourneyHistoryList({
    super.key,
    required this.childEmail,
    this.limit = 50,
    this.shrinkWrap = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final stream = UserPaths.child(childEmail)
        .collection('journeys')
        .orderBy('startedAt', descending: true)
        .limit(limit)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Could not load journeys: ${snap.error}'),
          );
        }
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text("No journeys yet")),
          );
        }
        return ListView.separated(
          shrinkWrap: shrinkWrap,
          physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final d = docs[i].data();
            final status = (d['status'] ?? '').toString();
            final started = (d['startedAt'] as Timestamp?)?.toDate();
            final ended = (d['endedAt'] as Timestamp?)?.toDate();
            final when = started == null
                ? ''
                : DateFormat('dd MMM yyyy, hh:mm a').format(started);
            final took = (started != null && ended != null)
                ? ' · ${ended.difference(started).inMinutes} min'
                : '';
            final (Color color, String label, IconData icon) = switch (status) {
              'active' => (Colors.blue, 'In progress', Icons.navigation),
              'completed' => (Colors.green, 'Reached', Icons.check_circle),
              _ => (Colors.orange, 'Ended early', Icons.stop_circle_outlined),
            };
            return Card(
              color: Theme.of(context).cardColor,
              elevation: isDark ? 0 : 1,
              child: ListTile(
                leading: Icon(icon, color: color),
                title: Text('${d['from'] ?? '?'} → ${d['to'] ?? '?'}',
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text('$when$took'),
                trailing: Text(label,
                    style: TextStyle(color: color, fontWeight: FontWeight.w600)),
              ),
            );
          },
        );
      },
    );
  }
}
