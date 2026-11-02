import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:sos_system/core/app_theme.dart';
import 'package:sos_system/services/profile_service.dart';

/// Round avatar: the person's profile photo, or their initial on teal.
/// [role] is the collection the person lives in ('Child' or 'Guardian').
class UserAvatar extends StatelessWidget {
  final String role;
  final String email;
  final String name;
  final double radius;
  final Color? ring;

  const UserAvatar({
    super.key,
    required this.role,
    required this.email,
    required this.name,
    this.radius = 22,
    this.ring,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Uint8List?>(
      stream: ProfileService.photoOf(role, email),
      initialData: ProfileService.cached(email),
      builder: (context, snap) {
        final bytes = snap.data;
        final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
        final avatar = CircleAvatar(
          radius: radius,
          backgroundColor: TG.softOf(context),
          backgroundImage: bytes == null ? null : MemoryImage(bytes),
          child: bytes == null
              ? Text(initial,
                  style: TextStyle(
                    fontSize: radius * 0.8,
                    fontWeight: FontWeight.w800,
                    color: TG.accentTextOf(context),
                  ))
              : null,
        );
        if (ring == null) return avatar;
        return CircleAvatar(radius: radius + 2, backgroundColor: ring, child: avatar);
      },
    );
  }
}
