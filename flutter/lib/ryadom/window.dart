import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';
import 'package:window_size/window_size.dart' as screens;

Future<void> configureRyadomMainWindow() async {
  var screen = await screens.getCurrentScreen();
  if (screen == null) {
    final available = await screens.getScreenList();
    if (available.isNotEmpty) screen = available.first;
  }
  final dpi = screen?.scaleFactor ?? 1;
  final availableWidth =
      math.max(320.0, (screen?.visibleFrame.width ?? 1280) / dpi - 24);
  final availableHeight =
      math.max(280.0, (screen?.visibleFrame.height ?? 800) / dpi - 24);
  final views = WidgetsBinding.instance.platformDispatcher.views;
  final textScale = (views.isEmpty
          ? 1.0
          : MediaQueryData.fromView(views.first).textScaler.scale(1))
      .clamp(1.0, 1.5)
      .toDouble();
  await windowManager.setMinimumSize(
      Size(math.min(760.0, availableWidth), math.min(440.0, availableHeight)));
  if (await windowManager.isMaximized()) return;
  await windowManager.setSize(Size(math.min(920.0, availableWidth),
      math.min(560.0 * textScale, availableHeight)));
  await windowManager.center();
}
