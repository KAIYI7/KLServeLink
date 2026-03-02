import 'package:flutter/material.dart';
import 'package:fyp_flutter/features/chat/screens/provider_inbox_tab.dart';
import 'package:fyp_flutter/features/provider/insights/screens/provider_insights_tab.dart';
import 'package:fyp_flutter/features/provider/services/screens/provider_services_tab.dart';
import '../core/widgets/ui_components.dart';
import '../features/provider/dashboard/screens/provider_dashboard_tab.dart';
import '../features/provider/bookings/screens/provider_bookings_tab.dart';
import '../features/provider/profile/screens/provider_profile_tab.dart';
import 'provider_shell_scope.dart';

class ProviderShell extends StatefulWidget {
  const ProviderShell({super.key});

  @override
  State<ProviderShell> createState() => _ProviderShellState();
}

/// Observer that notifies whenever routes change (push/pop/etc)
class _TabNavObserver extends NavigatorObserver {
  final VoidCallback onChanged;
  _TabNavObserver({required this.onChanged});

  void _notify() => onChanged();

  @override
  void didPush(Route route, Route? previousRoute) => _notify();

  @override
  void didPop(Route route, Route? previousRoute) => _notify();

  @override
  void didRemove(Route route, Route? previousRoute) => _notify();

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) => _notify();
}

class _ProviderShellState extends State<ProviderShell> {
  int index = 0;

  static const _icons = <IconData>[
    Icons.dashboard_rounded,
    Icons.storefront_rounded,          // Services
    Icons.calendar_month_rounded,      // Bookings
    Icons.chat_bubble_outline_rounded, // Inbox
    Icons.insights_rounded,            // Insights
    Icons.person_outline,              // Profile
  ];

  final pages = const [
    ProviderDashboardTab(),
    ProviderServicesTab(),
    ProviderBookingsTab(),
    ProviderInboxTab(),
    ProviderInsightsTab(),
    ProviderProfileTab(),
  ];

  late final List<GlobalKey<NavigatorState>> _navKeys;
  late final List<_TabNavObserver> _observers;

  // track whether each tab navigator can pop
  late final List<bool> _canPop;

  @override
  void initState() {
    super.initState();
    _navKeys = List.generate(pages.length, (_) => GlobalKey<NavigatorState>());
    _canPop = List<bool>.filled(pages.length, false);

    _observers = List.generate(
      pages.length,
          (i) => _TabNavObserver(
        onChanged: () => _refreshCanPop(i),
      ),
    );

    // initial check after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (int i = 0; i < pages.length; i++) {
        _refreshCanPop(i);
      }
    });
  }

  void _refreshCanPop(int i) {
    if (!mounted) return;
    // schedule after current frame so navigator state is updated
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nav = _navKeys[i].currentState;
      final can = nav?.canPop() ?? false;
      if (_canPop[i] != can) {
        setState(() => _canPop[i] = can);
      } else {
        if (i == index) setState(() {});
      }
    });
  }

  void _setIndex(int i) {
    if (i == index) {
      _navKeys[i].currentState?.popUntil((r) => r.isFirst);
      _refreshCanPop(i);
      return;
    }
    setState(() => index = i);
    _refreshCanPop(i);
  }

  Future<bool> _onWillPop() async {
    final nav = _navKeys[index].currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();
      _refreshCanPop(index);
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final showBottomNav = !(_canPop[index]);

    return ProviderShellScope(
      index: index,
      setIndex: _setIndex,
      child: WillPopScope(
        onWillPop: _onWillPop,
        child: Scaffold(
          body: Stack(
            children: [
              IndexedStack(
                index: index,
                children: List.generate(pages.length, (i) {
                  return Navigator(
                    key: _navKeys[i],
                    observers: [_observers[i]],
                    onGenerateRoute: (settings) => MaterialPageRoute(
                      builder: (_) => pages[i],
                      settings: settings,
                    ),
                  );
                }),
              ),

              // Glass nav only when on the tab root screen
              if (showBottomNav)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: GlassBottomNav(
                    index: index,
                    icons: _icons,
                    onChanged: _setIndex,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
