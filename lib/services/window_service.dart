import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

class WindowService {
  static final WindowService instance = WindowService._();
  WindowService._();

  bool _isInitialized = false;
  double? _overlayHeight;

  Future<void> initialize({double heightRatio = 0.60, double minHeight = 480}) async {
    if (_isInitialized) return;

    await windowManager.ensureInitialized();

    final display = await screenRetriever.getPrimaryDisplay();
    final usableSize = display.visibleSize ?? display.size;
    final origin = display.visiblePosition ?? Offset.zero;

    _overlayHeight = math.max(minHeight, (usableSize.height * heightRatio).roundToDouble());

    final windowOptions = WindowOptions(
      size: Size(usableSize.width, _overlayHeight!),
      minimumSize: Size(usableSize.width, _overlayHeight!),
      maximumSize: Size(usableSize.width, _overlayHeight!),
      skipTaskbar: true,
      center: false,
      backgroundColor: Colors.transparent,
      titleBarStyle: TitleBarStyle.hidden,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setResizable(false);
      await windowManager.setSkipTaskbar(true);
      await windowManager.setAlignment(Alignment.bottomCenter);

      final y = origin.dy + usableSize.height - _overlayHeight!;
      await windowManager.setPosition(Offset(origin.dx, y));
      await windowManager.hide();
    });

    _isInitialized = true;
  }

  double? get overlayHeight => _overlayHeight;

  Future<void> show() async {
    if (!_isInitialized) throw StateError('WindowService not initialized');

    await _ensureBounds();
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

  Future<void> _ensureBounds() async {
    final display = await screenRetriever.getPrimaryDisplay();
    final usableSize = display.visibleSize ?? display.size;
    final origin = display.visiblePosition ?? Offset.zero;

    if (_overlayHeight == null) return;

    await windowManager.setSize(
      Size(usableSize.width, _overlayHeight!),
      animate: false,
    );
    await windowManager.setPosition(
      Offset(origin.dx, origin.dy + usableSize.height - _overlayHeight!),
      animate: false,
    );
    await windowManager.setAlignment(Alignment.bottomCenter);
  }
}
