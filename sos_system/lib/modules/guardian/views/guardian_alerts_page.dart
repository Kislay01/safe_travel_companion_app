import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sos_system/common/views/custom_appbar.dart';
import 'package:sos_system/core/user_paths.dart';
import 'package:sos_system/modules/guardian/views/guardian_notifications_page.dart';
import 'package:url_launcher/url_launcher.dart';

/// Journey, SOS and check-in alerts for a guardian (newest first).
class GuardianAlertsPage extends StatelessWidget {
  final String guardianEmail;
  const GuardianAlertsPage({super.key, required this.guardianEmail});

  static (IconData, Color) _style(String type, Map<String, dynamic> d) {
    switch (type) {
      case 'sos':
        return (Icons.sos, Colors.red);
      case 'journey_started':
        return (Icons.navigation, Colors.blue);
      case 'journey_completed':
        return (Icons.check_circle, Colors.green);
      case 'journey_ended':
        return (Icons.stop_circle_outlined, Colors.orange);
      case 'checkin_response':
        return d['status'] == 'help'
            ? (Icons.sos, Colors.red)
            : (Icons.health_and_safety, Colors.green);
      case 'link_accepted':
        return (Icons.link, Colors.teal);
      default:
        return (Icons.notifications, Colors.grey);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stream = UserPaths.guardian(guardianEmail)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots();

    return Scaffold(
      appBar: CustomAppBar(
        title: "Alerts",
        actions: [
          IconButton(
            tooltip: 'Link requests',
            icon: const Icon(Icons.person_add_alt_1_outlined, color: Colors.blue),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const GuardianNotificationsPage()),
            ),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text("No alerts yet"));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final d = docs[i].data();
              final type = (d['type'] ?? '').toString();
              final (icon, color) = _style(type, d);
              final at = (d['createdAt'] as Timestamp?)?.toDate();
              final lat = d['latitude'];
              final lng = d['longitude'];
              final hasLocation = lat is num && lng is num;
              return Card(
                child: ListTile(
                  leading: Icon(icon, color: color, size: 30),
                  title: Text((d['title'] ?? '').toString(),
                      style: TextStyle(
                          fontWeight: d['read'] == true ? FontWeight.normal : FontWeight.w700)),
                  subtitle: Text([
                    (d['body'] ?? '').toString(),
                    if (at != null) DateFormat('dd MMM, hh:mm a').format(at),
                  ].join('\n')),
                  isThreeLine: true,
                  trailing: hasLocation
                      ? IconButton(
                          tooltip: 'Open in Maps',
                          icon: const Icon(Icons.map_outlined),
                          onPressed: () => launchUrl(
                            Uri.parse('https://maps.google.com/?q=$lat,$lng'),
                            mode: LaunchMode.externalApplication,
                          ),
                        )
                      : null,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
