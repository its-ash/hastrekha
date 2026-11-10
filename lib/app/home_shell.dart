import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../ui/history/history_screen.dart';
import '../ui/home/home_screen.dart';
import '../ui/library/library_screen.dart';
import '../ui/profile/profile_screen.dart';

/// Bottom navigation: Home, Readings, Library, Profile.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  /// Lets inner screens switch tabs (e.g. "See all readings").
  static void goTo(BuildContext context, int tab) =>
      context.findAncestorStateOfType<_HomeShellState>()?._select(tab);

  static const home = 0, readings = 1, library = 2, profile = 3;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  void _select(int i) => setState(() => _tab = i);

  @override
  Widget build(BuildContext context) {
    return UiShell(
      index: _tab,
      onChanged: _select,
      items: const [
        UiNavItem(Icons.back_hand_outlined, 'Home', selectedIcon: Icons.back_hand_rounded),
        UiNavItem(Icons.history_rounded, 'Readings'),
        UiNavItem(Icons.menu_book_outlined, 'Library', selectedIcon: Icons.menu_book_rounded),
        UiNavItem(Icons.person_outline_rounded, 'Profile', selectedIcon: Icons.person_rounded),
      ],
      pages: const [HomeScreen(), HistoryScreen(), LibraryScreen(), ProfileScreen()],
    );
  }
}
