import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

const double _overlayHeightRatio = 0.20;
final HotKey _toggleHotKey = HotKey(
  key: PhysicalKeyboardKey.keyV,
  modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
  scope: HotKeyScope.system,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  final display = await screenRetriever.getPrimaryDisplay();
  final usableSize = display.visibleSize ?? display.size;
  final origin = display.visiblePosition ?? Offset.zero;
  final double overlayHeight = math.max(
    360,
    (usableSize.height * _overlayHeightRatio).roundToDouble(),
  );

  final windowOptions = WindowOptions(
    size: Size(usableSize.width, overlayHeight),
    minimumSize: Size(usableSize.width, overlayHeight),
    maximumSize: Size(usableSize.width, overlayHeight),
    skipTaskbar: true,
    center: false,
    backgroundColor: Colors.transparent,
    titleBarStyle: TitleBarStyle.hidden,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setResizable(false);
    await windowManager.setHasShadow(false);
    await windowManager.setSkipTaskbar(true);

    final double y = origin.dy + usableSize.height - overlayHeight;
    await windowManager.setPosition(Offset(origin.dx, y));
    await windowManager.hide();
  });

  runApp(PasteProApp(
    overlayHeight: overlayHeight,
  ));
}

class PasteProApp extends StatefulWidget {
  const PasteProApp({
    super.key,
    required this.overlayHeight,
  });

  final double overlayHeight;

  @override
  State<PasteProApp> createState() => _PasteProAppState();
}

class _PasteProAppState extends State<PasteProApp>
    with WindowListener {
  bool _isVisible = false;
  late final VoidCallback _trayActivateHandler = () => unawaited(_toggleOverlay());

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    unawaited(_initialiseTray());
    unawaited(_registerHotKey());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    unawaited(hotKeyManager.unregister(_toggleHotKey));
    TrayBridge.instance.removeActivateHandler(_trayActivateHandler);
    super.dispose();
  }

  Future<void> _registerHotKey() async {
    await hotKeyManager.unregisterAll();
    await hotKeyManager.register(
      _toggleHotKey,
      keyDownHandler: (_) => _toggleOverlay(),
    );
  }

  Future<void> _initialiseTray() async {
    if (!Platform.isLinux) {
      return;
    }
    final iconFile = File('assets/icons/clipboard.png');
    try {
      if (await iconFile.exists()) {
        await TrayBridge.instance.setIcon(
          iconFile.absolute.path,
          tooltip: 'PastePro • Ctrl+Shift+V',
        );
      }
      TrayBridge.instance.addActivateHandler(_trayActivateHandler);
    } catch (error) {
      debugPrint('Tray initialisation failed: $error');
    }
  }

  Future<void> _toggleOverlay() async {
    final bool currentlyVisible = await windowManager.isVisible();
    if (currentlyVisible) {
      await windowManager.hide();
      await windowManager.setAlwaysOnTop(false);
    } else {
      await _ensureBounds();
      await windowManager.setAlwaysOnTop(true);
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setAlwaysOnTop(false);
    }
    if (mounted) {
      setState(() => _isVisible = !currentlyVisible);
    }
  }

  Future<void> _ensureBounds() async {
    final display = await screenRetriever.getPrimaryDisplay();
    final usableSize = display.visibleSize ?? display.size;
    final origin = display.visiblePosition ?? Offset.zero;
    final double overlayHeight = widget.overlayHeight;
    await windowManager.setSize(
      Size(usableSize.width, overlayHeight),
      animate: false,
    );
    await windowManager.setPosition(
      Offset(origin.dx, origin.dy + usableSize.height - overlayHeight),
      animate: false,
    );
  }

  @override
  void onWindowBlur() {
    unawaited(windowManager.hide());
    if (mounted) {
      setState(() => _isVisible = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PastePro',
      theme: ThemeData(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF64FFDA),
          secondary: Color(0xFF1F2933),
          surface: Color(0xFF0B0F14),
        ),
        scaffoldBackgroundColor: Colors.transparent,
        useMaterial3: true,
      ),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                height: widget.overlayHeight,
                decoration: BoxDecoration(
                  color: const Color(0xFF101720).withOpacity(0.96),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                  border: Border.all(color: Colors.white12, width: 1.2),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 18,
                      spreadRadius: 2,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: const _OverlayContent(),
              ),
            ),
            Positioned(
              right: 24,
              bottom: 28,
              child: AnimatedOpacity(
                opacity: _isVisible ? 1 : 0.0,
                duration: const Duration(milliseconds: 180),
                child: const _ShortcutBadge(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShortcutBadge extends StatelessWidget {
  const _ShortcutBadge();

  @override
  Widget build(BuildContext context) {
    final Color borderColor = Colors.white.withOpacity(0.08);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.keyboard_command_key, size: 18, color: Colors.white70),
          SizedBox(width: 8),
          Text('Ctrl + Shift + V to toggle', style: TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}

class _OverlayContent extends StatelessWidget {
  const _OverlayContent();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: const [
            Text('📋 PastePro', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            Spacer(),
            Icon(Icons.push_pin_outlined, color: Colors.white54, size: 20),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Overlay ready. Keep typing anywhere – tap Ctrl+Shift+V to pull me up again.',
          style: TextStyle(color: Colors.white.withOpacity(0.72)),
        ),
        const SizedBox(height: 32),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: const TextField(
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Search recent clips…',
              border: InputBorder.none,
            ),
            style: TextStyle(color: Colors.white),
          ),
        ),
      ],
    );
  }
}

class TrayBridge {
  TrayBridge._();

  static final TrayBridge instance = TrayBridge._();
  static const MethodChannel _channel = MethodChannel('pastepro/tray');

  final List<VoidCallback> _activateHandlers = <VoidCallback>[];
  bool _handlerAttached = false;

  Future<void> setIcon(String iconPath, {required String tooltip}) async {
    if (!_handlerAttached) {
      _channel.setMethodCallHandler(_handleMethodCall);
      _handlerAttached = true;
    }
    await _channel.invokeMethod('setIcon', {
      'iconPath': iconPath,
      'tooltip': tooltip,
    });
  }

  void addActivateHandler(VoidCallback handler) {
    _activateHandlers.add(handler);
  }

  void removeActivateHandler(VoidCallback handler) {
    _activateHandlers.remove(handler);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onActivate') {
      final callbacks = List<VoidCallback>.from(_activateHandlers);
      for (final callback in callbacks) {
        callback();
      }
    }
  }
}
