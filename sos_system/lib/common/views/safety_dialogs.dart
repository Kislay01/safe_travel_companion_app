import 'dart:async';

import 'package:flutter/material.dart';

/// 5-second countdown before an automatic (voice) SOS. Returns true to send.
class SosCountdownDialog extends StatefulWidget {
  final int seconds;
  final String reason;
  const SosCountdownDialog({super.key, this.seconds = 5, required this.reason});

  @override
  State<SosCountdownDialog> createState() => _SosCountdownDialogState();
}

class _SosCountdownDialogState extends State<SosCountdownDialog> {
  late int _left = widget.seconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_left <= 1) {
        t.cancel();
        Navigator.of(context).pop(true);
      } else {
        setState(() => _left--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sending SOS'),
      content: Text('${widget.reason}\n\nSOS will be sent in $_left s.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Send now'),
        ),
      ],
    );
  }
}

/// Shown on the child's phone when a guardian asks "Are you OK?".
/// Returns true for "I'm OK", false for "Need help", null if dismissed.
class CheckinDialog extends StatelessWidget {
  final String guardianName;
  const CheckinDialog({super.key, required this.guardianName});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.health_and_safety, size: 40, color: Colors.orange),
      title: const Text('Are you OK?'),
      content: Text('$guardianName is checking on you. Let them know you are safe.'),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.of(context).pop(false),
          icon: const Icon(Icons.sos),
          label: const Text('Need help'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Colors.green),
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.check),
          label: const Text("I'm OK"),
        ),
      ],
    );
  }
}
