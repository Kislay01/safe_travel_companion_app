import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:sos_system/common/views/profile_screen.dart';
import 'package:sos_system/modules/guardian/views/guardian_chat_list.dart';
import 'package:sos_system/modules/guardian/views/guardian_dashboard.dart';
import 'package:sos_system/modules/guardian/views/track_child_screen.dart';

class GuardianBottomNav extends StatefulWidget {
  final String guardianEmail; // 👈 Added to receive guardian’s email

  const GuardianBottomNav({super.key, required this.guardianEmail});

  @override
  State<GuardianBottomNav> createState() => _BottomNavbarState();
}

class _BottomNavbarState extends State<GuardianBottomNav> {
  int currentSelectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      GuardianDashboard(
        guardianEmail: widget.guardianEmail,
        onOpenTab: (i) => setState(() => currentSelectedIndex = i),
      ),
      TrackChild(guardianEmail: widget.guardianEmail),
      const ProfileScreen(),
      const GuardianChatList(),
    ];

    return PopScope(
      canPop: currentSelectedIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && currentSelectedIndex != 0) {
          setState(() => currentSelectedIndex = 0);
        }
      },
      child: Scaffold(
        body: IndexedStack(index: currentSelectedIndex, children: pages),
        bottomNavigationBar: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: currentSelectedIndex,
          selectedItemColor: Colors.blue,
          unselectedItemColor: Colors.grey,
          onTap: (value) {
            log("Index: $value");
            setState(() => currentSelectedIndex = value);
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home),
              label: "Home",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.map),
              label: "Track Child",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people),
              label: "Profile",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.chat),
              label: "Chat",
            ),
          ],
        ),
      ),
    );
  }
}
