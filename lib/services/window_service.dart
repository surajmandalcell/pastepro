import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

class WindowService {
  static final WindowService instance = WindowService._();
  WindowService._();

  bool _isInitialized = false;
  double? _overlayHeight;
  double _defaultRatio = 0.38; // between 0.36 and 0.40
  double _minHeight = 420;

  Future<void> initialize({double heightRatio = 0.38, double minHeight = 420}) async {
    if (_isInitialized) return;

    await windowManager.ensureInitialized();
    _defaultRatio = heightRatio;
    _minHeight = minHeight;

    final windowOptions = WindowOptions(
      // Size will be applied per-active-monitor on show().
      skipTaskbar: true,
      center: false,
      backgroundColor: Colors.transparent,
      titleBarStyle: TitleBarStyle.hidden,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setResizable(false);
      await windowManager.setSkipTaskbar(true);
      await windowManager.hide();
    });

    _isInitialized = true;
  }

  double? get overlayHeight => _overlayHeight;

  Future<void> show() async {
    if (!_isInitialized) throw StateError('WindowService not initialized');
    await _applyActiveMonitorBounds();
    await windowManager.show();
    await windowManager.setAlwaysOnTop(true);
    await windowManager.focus();
  }

  Future<void> hide() async {
    if (!_isInitialized) return;

    await windowManager.hide();
    await windowManager.setAlwaysOnTop(false);
  }

  Future<bool> isVisible() async {
    if (!_isInitialized) return false;
    return await windowManager.isVisible();
  }

  Future<void> _applyActiveMonitorBounds() async {
    final cursor = await screenRetriever.getCursorScreenPoint();
    final displays = await screenRetriever.getAllDisplays();
    var display = await screenRetriever.getPrimaryDisplay();

    for (final d in displays) {
      final pos = d.visiblePosition ?? Offset.zero;
      final size = d.visibleSize ?? d.size;
      final rect = Rect.fromLTWH(pos.dx, pos.dy, size.width, size.height);
      if (rect.contains(Offset(cursor.dx, cursor.dy))) {
        display = d;
        break;
      }
    }

    final usableSize = display.visibleSize ?? display.size;
    final origin = display.visiblePosition ?? Offset.zero;
    final ratio = _chooseRatio(usableSize.height);
    _overlayHeight = math.max(_minHeight, (usableSize.height * ratio).roundToDouble());

    await windowManager.setSize(Size(usableSize.width, _overlayHeight!), animate: false);
    final y = origin.dy + usableSize.height - _overlayHeight!;
    await windowManager.setPosition(Offset(origin.dx, y), animate: false);
  }

  double _chooseRatio(double h) {
    // Bias: 0.36 on >=1440p, 0.38 on >=1080p, else 0.40
    if (h >= 1440) return 0.36;
    if (h >= 1080) return 0.38;
    return 0.40;
  }
}
