import 'package:flutter/material.dart';
import 'bookings_tab.dart';
import 'chat_tab.dart';
import 'ui_components.dart';
import 'profile_tab.dart';
import 'seeker_home_screen.dart';
import 'search_screen.dart';
import 'seeker_nav_controller.dart';
import 'chat_detail_screen.dart';
import 'package:fyp_flutter/notifications/seeker_nav_registry.dart';

class SeekerShell extends StatefulWidget {
  const SeekerShell({super.key});

  @override
  State<SeekerShell> createState() => _SeekerShellState();
}

class _SeekerShellState extends State<SeekerShell> {
  int index = 0;

  late final SeekerNavController nav;

  static const _icons = <IconData>[
    Icons.home_rounded,
    Icons.search_rounded,
    Icons.calendar_month_rounded,
    Icons.chat_bubble_outline,
    Icons.person_outline,
  ];

  @override
  void initState() {
    super.initState();
    nav = SeekerNavController();
    SeekerNavRegistry.I.current = nav;
    nav.openChatWith.addListener(_handleOpenChatIntent);
  }

  @override
  void dispose() {
    nav.openChatWith.removeListener(_handleOpenChatIntent);
    nav.dispose();
    if (SeekerNavRegistry.I.current == nav) {
      SeekerNavRegistry.I.current = null;
    }
    super.dispose();
  }

  void _handleOpenChatIntent() {
    final peerUid = nav.openChatWith.value;
    if (peerUid == null) return;

    nav.tabIndex.value = 3;
    nav.openChatWith.value = null;

    // push after current frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ChatDetailScreen(peerUid: peerUid)),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      SeekerHomeScreen(nav: nav),
      SearchScreen(nav: nav),
      BookingsTab(nav: nav),
      ChatTab(nav: nav),
      ProfileTab(nav: nav),
    ];

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          ValueListenableBuilder<int>(
            valueListenable: nav.tabIndex,
            builder: (_, idx, __) {
              return IndexedStack(index: idx, children: pages);
            },
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: ValueListenableBuilder<int>(
              valueListenable: nav.tabIndex,
              builder: (_, idx, __) {
                return GlassBottomNav(
                  index: idx,
                  icons: _icons,
                  onChanged: (i) => nav.tabIndex.value = i,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
