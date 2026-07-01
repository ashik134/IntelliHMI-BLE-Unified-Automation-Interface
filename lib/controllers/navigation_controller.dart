import 'package:flutter/material.dart';

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
