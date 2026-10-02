import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sos_system/modules/auth/controllers/shared_preference_data.dart';
import 'package:sos_system/services/checkin_service.dart';

/// Sends an "Are you OK?" check-in to a child and shows the live reply.
Future<void> sendCheckinAndShowStatus(
  BuildContext context, {
  required String childEmail,
  required String childName,
}) async {
  final prefs = SharedPreferenceData();
  await prefs.getSharedPreferenceData();
  DocumentReference<Map<String, dynamic>> ref;
  try {
    ref = await CheckinService.send(
      childEmail: childEmail,
      guardianEmail: prefs.email,
      guardianName: prefs.name.isNotEmpty ? prefs.name : prefs.email,
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not send check-in: $e')));
    }
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _CheckinStatusDialog(ref: ref, childName: childName),
  );
}

class _CheckinStatusDialog extends StatelessWidget {
  final DocumentReference<Map<String, dynamic>> ref;
  final String childName;
  const _CheckinStatusDialog({required this.ref, required this.childName});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, snap) {
        final status = (snap.data?.data()?['status'] ?? 'pending').toString();
        late final Widget icon;
        late final String text;
        switch (status) {
          case 'ok':
            icon = const Icon(Icons.check_circle, color: Colors.green, size: 48);
            text = '$childName says they are OK.';
            break;
          case 'help':
            icon = const Icon(Icons.sos, color: Colors.red, size: 48);
            text = '$childName needs help! SOS has been triggered — check your alerts and call them.';
            break;
          default:
            icon = const SizedBox(
                width: 40, height: 40, child: CircularProgressIndicator());
            text = 'Waiting for $childName to reply…\n'
                'Their phone is vibrating with an "Are you OK?" alert. '
                'If there is no reply in a couple of minutes, call them.';
        }
        return AlertDialog(
          icon: icon,
          title: const Text('Check-in sent'),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(status == 'pending' ? 'Close (keep waiting)' : 'Close'),
            ),
          ],
        );
      },
    );
  }
}
