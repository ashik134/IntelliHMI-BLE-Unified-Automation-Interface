import 'package:flutter/material.dart';

/// Shared slide+fade push transition — the same recipe already used for the
/// control-subshell route in main.dart, extracted so the Widget Catalog push
/// doesn't duplicate it a third time. [beginOffset] defaults to a full
/// horizontal slide-in from the right for a distinct "new page" feel; pass a
/// smaller offset (e.g. the app's existing Offset(0.025, 0)) for a subtler
/// "settle in" transition instead.
Route<T> buildSlideFadeRoute<T>(
  WidgetBuilder builder, {
  Offset beginOffset = const Offset(1, 0),
}) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final offset = Tween<Offset>(
        begin: beginOffset,
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
      return FadeTransition(
        opacity: animation,
        child: SlideTransition(position: offset, child: child),
      );
    },
  );
}
