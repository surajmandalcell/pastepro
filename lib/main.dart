import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'models/clipboard_item.dart';
import 'services/clipboard_service.dart';
import 'services/single_instance_manager.dart';
import 'services/window_service.dart';
import 'settings_panel.dart';

const double _overlayHeightRatio = 0.60;
final HotKey _toggleHotKey = HotKey(
  key: PhysicalKeyboardKey.backslash,
  modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
  scope: HotKeyScope.system,
);

Future<void> main() async {
  // Wrap everything in error handling
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Single instance check
    if (!await SingleInstanceManager.instance.ensureSingleInstance()) {
      exit(0);
    }

    // Initialize window service
    await WindowService.instance.initialize(
      heightRatio: _overlayHeightRatio,
      minHeight: 480,
    );

    runApp(const PasteProApp());
  }, (error, stack) {
    // In debug/dev runs, avoid exiting the process to keep `flutter run` alive.
    // In release, still avoid abrupt termination; log and let Flutter error UI show.
    debugPrint('Fatal error: $error\n$stack');
  });
}

class PasteProApp extends StatefulWidget {
  const PasteProApp({super.key});

  @override
  State<PasteProApp> createState() => _PasteProAppState();
}

class _PasteProAppState extends State<PasteProApp>
    with SingleTickerProviderStateMixin, WindowListener {
  late final AnimationController _animationController;
  late final Animation<double> _slideAnimation;
  late final Animation<double> _fadeAnimation;
  late final VoidCallback _trayActivateHandler = () => unawaited(_toggleOverlay());

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 280),
      vsync: this,
    );

    _slideAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );

    windowManager.addListener(this);
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    try {
      await _initializeTray();
      await _registerHotKey();
      _setupSignalHandling();
      ClipboardService.instance.startMonitoring();
    } catch (e) {
      debugPrint('Service initialization error: $e');
    }
  }

  @override
  void dispose() {
    ClipboardService.instance.dispose();
    _animationController.dispose();
    windowManager.removeListener(this);
    unawaited(hotKeyManager.unregister(_toggleHotKey));
    TrayBridge.instance.removeActivateHandler(_trayActivateHandler);
    SingleInstanceManager.instance.cleanup();
    super.dispose();
  }

  void _setupSignalHandling() {
    if (Platform.isLinux) {
      ProcessSignal.sigusr1.watch().listen((_) {
        unawaited(_toggleOverlay());
      });
    }
  }

  Future<void> _registerHotKey() async {
    if (Platform.environment['XDG_SESSION_TYPE'] == 'wayland') {
      debugPrint('Wayland detected - using signal-based toggle (Ctrl+Shift+\\)');
      return;
    }

    try {
      await hotKeyManager.unregisterAll();
      await hotKeyManager.register(
        _toggleHotKey,
        keyDownHandler: (_) => _toggleOverlay(),
      );
    } catch (e) {
      debugPrint('Hotkey registration error: $e');
    }
  }

  Future<void> _initializeTray() async {
    if (!Platform.isLinux) return;

    try {
      final iconFile = File('assets/icons/clipboard.png');
      if (await iconFile.exists()) {
        await TrayBridge.instance.setIcon(
          iconFile.absolute.path,
          tooltip: 'PastePro • Ctrl+Shift+\\',
        );
      }
      TrayBridge.instance.addActivateHandler(_trayActivateHandler);
      TrayBridge.instance.addExitHandler(() async {
        // Gracefully hide instead of exiting the Flutter process.
        await WindowService.instance.hide();
        await SingleInstanceManager.instance.cleanup();
      });
    } catch (error) {
      debugPrint('Tray initialization failed: $error');
    }
  }

  Future<void> _toggleOverlay() async {
    try {
      final currentlyVisible = await WindowService.instance.isVisible();
      if (currentlyVisible) {
        await _animationController.reverse();
        await WindowService.instance.hide();
      } else {
        await WindowService.instance.show();
        await _animationController.forward();
      }
    } catch (e) {
      debugPrint('Toggle error: $e');
    }
  }

  @override
  void onWindowBlur() {
    unawaited(_animationController.reverse().then((_) async {
      await WindowService.instance.hide();
    }));
  }

  @override
  Widget build(BuildContext context) {
    final overlayHeight = WindowService.instance.overlayHeight ?? 480;

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
        body: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return Align(
              alignment: Alignment.bottomCenter,
              child: Transform.translate(
                offset: Offset(0, (1 - _slideAnimation.value) * 50),
                child: Opacity(
                  opacity: _fadeAnimation.value,
                  child: child,
                ),
              ),
            );
          },
          child: Container(
            width: double.infinity,
            height: overlayHeight,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF1A1F2E).withOpacity(0.98),
                  const Color(0xFF0F1419).withOpacity(0.98),
                ],
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 40,
                  spreadRadius: 0,
                  offset: const Offset(0, -10),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
            child: const _OverlayContent(),
          ),
        ),
      ),
    );
  }
}

class _OverlayContent extends StatefulWidget {
  const _OverlayContent();

  @override
  State<_OverlayContent> createState() => _OverlayContentState();
}

class _OverlayContentState extends State<_OverlayContent> with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late TabController _tabController;
  List<ClipboardItem> _clipboardItems = [];
  String _searchQuery = '';
  String _selectedCategory = 'history';

  final List<Map<String, String>> _categories = [
    {'id': 'history', 'name': 'History', 'icon': '📋'},
    {'id': 'links', 'name': 'Links', 'icon': '🔗'},
    {'id': 'notes', 'name': 'Notes', 'icon': '📝'},
    {'id': 'code', 'name': 'Code', 'icon': '💻'},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categories.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadClipboardItems();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) {
      setState(() {
        _selectedCategory = _categories[_tabController.index]['id']!;
      });
      _loadClipboardItems();
    }
  }

  Future<void> _loadClipboardItems() async {
    try {
      final items = await ClipboardService.instance.getItems(
        category: _selectedCategory == 'history' ? null : _selectedCategory,
      );
      if (mounted) {
        setState(() {
          _clipboardItems = items;
        });
      }
    } catch (e) {
      debugPrint('Failed to load items: $e');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF64FFDA).withOpacity(0.15),
                    const Color(0xFF00BFA5).withOpacity(0.15),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.content_paste_rounded, size: 24, color: Color(0xFF64FFDA)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                'PastePro',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined, color: Colors.white70),
              onPressed: () {
                showDialog(
                  context: context,
                  barrierColor: Colors.black54,
                  builder: (_) => const SettingsPanel(),
                );
              },
            ),
            Flexible(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 180),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.keyboard, size: 14, color: Colors.white.withOpacity(0.6)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Ctrl+Shift+\\',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            indicator: BoxDecoration(
              color: const Color(0xFF64FFDA).withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            labelColor: const Color(0xFF64FFDA),
            unselectedLabelColor: Colors.white.withOpacity(0.5),
            dividerColor: Colors.transparent,
            tabs: _categories.map((cat) {
              return Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(cat['icon']!, style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 8),
                    Text(
                      cat['name']!,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 20),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Search...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 15),
              prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.4), size: 22),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            ),
            onChanged: (value) {
              setState(() => _searchQuery = value.trim().toLowerCase());
            },
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: _filteredItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.content_paste, size: 64, color: Colors.white.withOpacity(0.2)),
                      const SizedBox(height: 16),
                      Text(
                        'No items yet',
                        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Copy something to get started',
                        style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _filteredItems.length,
                  itemBuilder: (context, index) {
                    final item = _filteredItems[index];
                    return _ClipboardItemCard(item: item);
                  },
                ),
        ),
      ],
    );
  }

  List<ClipboardItem> get _filteredItems {
    if (_searchQuery.isEmpty) return _clipboardItems;
    return _clipboardItems
        .where((e) => e.content.toLowerCase().contains(_searchQuery))
        .toList();
  }
}

class _ClipboardItemCard extends StatefulWidget {
  final ClipboardItem item;

  const _ClipboardItemCard({required this.item});

  @override
  State<_ClipboardItemCard> createState() => _ClipboardItemCardState();
}

class _ClipboardItemCardState extends State<_ClipboardItemCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _isHovered ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _isHovered ? Colors.white.withOpacity(0.12) : Colors.white.withOpacity(0.06),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.text_fields,
                    size: 16,
                    color: const Color(0xFF64FFDA),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.item.sourceApp ?? 'Unknown',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatTimestamp(widget.item.createdAt),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                widget.item.content,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }
}

class TrayBridge {
  TrayBridge._();

  static final TrayBridge instance = TrayBridge._();
  static const MethodChannel _channel = MethodChannel('pastepro/tray');

  final List<VoidCallback> _activateHandlers = <VoidCallback>[];
  final List<VoidCallback> _exitHandlers = <VoidCallback>[];
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

  void addExitHandler(VoidCallback handler) {
    _exitHandlers.add(handler);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onActivate') {
      final callbacks = List<VoidCallback>.from(_activateHandlers);
      for (final callback in callbacks) {
        callback();
      }
    } else if (call.method == 'onExit') {
      final callbacks = List<VoidCallback>.from(_exitHandlers);
      for (final callback in callbacks) {
        callback();
      }
    }
  }
}
