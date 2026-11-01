import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:sos_system/modules/child/views/child_chat_list.dart';
import 'package:sos_system/common/views/profile_screen.dart';
import 'package:sos_system/modules/child/views/child_dashboard.dart';
import 'package:sos_system/modules/child/views/journey_screen.dart';

class ChildBottomNav extends StatefulWidget {
  const ChildBottomNav({super.key});

  @override
  State<ChildBottomNav> createState() => _BottomNavbarState();
}

class _BottomNavbarState extends State<ChildBottomNav> {
  int currentSelectedIndex = 0;

  void _openTab(int index) => setState(() => currentSelectedIndex = index);

  // SOS lives on Home (big hold button) and on the Journey screen, so it no
  // longer needs its own tab.
  late final List<Widget> _pages = [
    ChildDashboard(onOpenTab: _openTab),
    const JourneyScreen(),
    ChildChatList(),
    ProfileScreen(),
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

        bottomNavigationBar: NavigationBar(
          selectedIndex: currentSelectedIndex,
          onDestinationSelected: (value) {
            log("Index: $value");
            setState(() => currentSelectedIndex = value);
          },
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Journey'),
            NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Chat'),
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}
