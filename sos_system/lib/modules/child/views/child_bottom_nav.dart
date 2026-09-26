import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:sos_system/modules/child/views/child_chat_list.dart';
import 'package:sos_system/common/views/profile_screen.dart';
import 'package:sos_system/modules/child/views/child_dashboard.dart';
import 'package:sos_system/modules/child/views/journey_screen.dart';
import 'package:sos_system/modules/child/views/sospage.dart';

class ChildBottomNav extends StatefulWidget {
  const ChildBottomNav({super.key});

  @override
  State<ChildBottomNav> createState() => _BottomNavbarState();
}

class _BottomNavbarState extends State<ChildBottomNav> {
  int currentSelectedIndex = 0;

  final List<Widget> _pages = [
    ChildDashboard(),
    JourneyScreen(),
    SOSPage(),
    ProfileScreen(),
    ChildChatList(),
  ];

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: currentSelectedIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          // 🧠 If not on dashboard, switch to dashboard instead of exiting
          if (currentSelectedIndex != 0) {
            setState(() {
              currentSelectedIndex = 0;
            });
          }
        }
      },

      child: Scaffold(
        body: IndexedStack(index: currentSelectedIndex, children: _pages),

        bottomNavigationBar: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: currentSelectedIndex,
          selectedItemColor: Colors.blue,
          unselectedItemColor: Colors.grey,
          onTap: (value) {
            log("Index: $value");
            setState(() {
              currentSelectedIndex = value;
            });
          },
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.home),
              label: "Home",
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.map),
              label: "Journey",
            ),

            // 🔴 Custom Red Circular SOS Button
            BottomNavigationBarItem(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Colors.red, // red circular background
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.sos,
                  color: Colors.white, // white SOS icon
                  size: 26,
                ),
              ),
              label: "SOS",
            ),

            const BottomNavigationBarItem(
              icon: Icon(Icons.people),
              label: "Profile",
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.chat),
              label: "Chat",
            ),
          ],
        ),
      ),
    );
  }
}
