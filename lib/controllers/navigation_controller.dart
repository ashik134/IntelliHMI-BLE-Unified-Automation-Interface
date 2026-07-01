import 'package:flutter/material.dart';

/// Centralised bottom-navigation state for the [MainShell].
///
/// Every entry point that needs to change the active tab (quick-action buttons,
/// the HomeScreen CTA card, programmatic deep-links, etc.) calls [navigateTo]
/// on this controller instead of managing a local index.  The [MainShell]
/// reads this controller and rebuilds its [IndexedStack] accordingly so the
/// Bottom Navigation Bar always reflects the current section.
class NavigationController extends ChangeNotifier {
  int _currentIndex = 0;

  int get currentIndex => _currentIndex;

  void navigateTo(int index) {
    assert(index >= 0 && index < 4, 'Index must be 0–3');
    if (_currentIndex == index) return;
    _currentIndex = index;
    notifyListeners();
  }

  void navigateToHome() => navigateTo(0);
  void navigateToControl() => navigateTo(1);
  void navigateToDiagnostics() => navigateTo(2);
  void navigateToLogs() => navigateTo(3);
}
