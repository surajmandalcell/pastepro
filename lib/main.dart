import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'database.dart';

const double _overlayHeightRatio = 0.60;
final HotKey _toggleHotKey = HotKey(
  key: PhysicalKeyboardKey.backslash,
  modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
  scope: HotKeyScope.system,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // Single instance check
  if (!await _ensureSingleInstance()) {
    exit(0);
  }

  final display = await screenRetriever.getPrimaryDisplay();
  final usableSize = display.visibleSize ?? display.size;
  final origin = display.visiblePosition ?? Offset.zero;
  final double overlayHeight = math.max(
    480,
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
    await windowManager.setSkipTaskbar(true);
    await windowManager.setAlignment(Alignment.bottomCenter);

    final double y = origin.dy + usableSize.height - overlayHeight;
    await windowManager.setPosition(Offset(origin.dx, y));
    await windowManager.hide();
  });

  runApp(PasteProApp(
    overlayHeight: overlayHeight,
  ));
}

Future<bool> _ensureSingleInstance() async {
  try {
    final appDir = await getApplicationDocumentsDirectory();
    final lockFile = File(path.join(appDir.path, 'pastepro', '.lock'));

    if (await lockFile.exists()) {
      // Try to read PID from lock file
      final pidStr = await lockFile.readAsString();
      final pid = int.tryParse(pidStr);

      if (pid != null) {
        // Check if process is still running
        final result = await Process.run('kill', ['-0', pid.toString()]);
        if (result.exitCode == 0) {
          // Process exists, kill it
          await Process.run('kill', [pid.toString()]);
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      await lockFile.delete();
    }

    // Create lock file with our PID
    await lockFile.parent.create(recursive: true);
    await lockFile.writeAsString(pid.toString());

    return true;
  } catch (e) {
    debugPrint('Single instance check failed: $e');
    return true; // Continue anyway
  }
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
    with SingleTickerProviderStateMixin, WindowListener {
  bool _isVisible = false;
  late final AnimationController _animationController;
  late final Animation<double> _slideAnimation;
  late final Animation<double> _fadeAnimation;
  late final VoidCallback _trayActivateHandler = () => unawaited(_toggleOverlay());
  Timer? _clipboardMonitor;

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
    unawaited(_initialiseTray());
    unawaited(_registerHotKey());
    _setupSignalHandling();
    _startClipboardMonitoring();
  }

  @override
  void dispose() {
    _clipboardMonitor?.cancel();
    _animationController.dispose();
    windowManager.removeListener(this);
    unawaited(hotKeyManager.unregister(_toggleHotKey));
    TrayBridge.instance.removeActivateHandler(_trayActivateHandler);
    _removeLockFile();
    super.dispose();
  }

  void _startClipboardMonitoring() {
    _clipboardMonitor = Timer.periodic(const Duration(seconds: 2), (timer) {
      _checkClipboard();
    });
  }

  Future<void> _checkClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data != null && data.text != null && data.text!.isNotEmpty) {
        await _saveClipboardItem(data.text!, 'text');
      }
    } catch (e) {
      // Clipboard access might fail, ignore
      debugPrint('Clipboard check error: $e');
    }
  }

  String? _lastClipboardContent;

  Future<void> _saveClipboardItem(String content, String type) async {
    // Avoid duplicates
    if (content == _lastClipboardContent) return;
    _lastClipboardContent = content;

    await ClipboardDatabase.instance.insertItem({
      'content': content,
      'type': type,
      'category': _categorizeContent(content),
      'source_app': 'Unknown',
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  String _categorizeContent(String content) {
    if (content.startsWith('http://') || content.startsWith('https://')) {
      return 'links';
    } else if (content.contains('struct') || content.contains('function') || content.contains('class')) {
      return 'code';
    } else if (content.length > 200) {
      return 'notes';
    }
    return 'history';
  }

  Future<void> _removeLockFile() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final lockFile = File(path.join(appDir.path, 'pastepro', '.lock'));
      if (await lockFile.exists()) {
        await lockFile.delete();
      }
    } catch (e) {
      debugPrint('Failed to remove lock file: $e');
    }
  }

  void _setupSignalHandling() {
    ProcessSignal.sigusr1.watch().listen((_) {
      unawaited(_toggleOverlay());
    });
  }

  Future<void> _registerHotKey() async {
    if (Platform.environment['XDG_SESSION_TYPE'] == 'wayland') {
      debugPrint('Wayland detected - using signal-based toggle (Ctrl+Shift+\\)');
      return;
    }

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
          tooltip: 'PastePro • Ctrl+Shift+\\',
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
      await _animationController.reverse();
      await windowManager.hide();
      await windowManager.setAlwaysOnTop(false);
    } else {
      await _ensureBounds();
      await windowManager.show();
      await windowManager.setAlwaysOnTop(true);
      await windowManager.focus();
      await _animationController.forward();
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
    await windowManager.setAlignment(Alignment.bottomCenter);
  }

  @override
  void onWindowBlur() {
    unawaited(_animationController.reverse().then((_) async {
      await windowManager.hide();
      if (mounted) {
        setState(() => _isVisible = false);
      }
    }));
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
            height: widget.overlayHeight,
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
  List<Map<String, dynamic>> _clipboardItems = [];
  String _selectedCategory = 'history';

  final List<Map<String, String>> _categories = [
    {'id': 'history', 'name': 'Clipboard History', 'icon': '📋'},
    {'id': 'links', 'name': 'Useful Links', 'icon': '🔗'},
    {'id': 'notes', 'name': 'Important Notes', 'icon': '📝'},
    {'id': 'code', 'name': 'Code Snippets', 'icon': '💻'},
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
    final items = await ClipboardDatabase.instance.getItems(
      category: _selectedCategory == 'history' ? null : _selectedCategory,
    );
    setState(() {
      _clipboardItems = items;
    });
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
        // Header with tabs
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
            const Text(
              'PastePro',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
            const Spacer(),
            Container(
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
                  Text(
                    'Ctrl+Shift+\\',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Category tabs
        Container(
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: TabBar(
            controller: _tabController,
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

        // Search bar
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
              hintText: 'Search clipboard history...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 15),
              prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.4), size: 22),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Clipboard items
        Expanded(
          child: _clipboardItems.isEmpty
              ? Center(
                  child: Text(
                    'No items yet',
                    style: TextStyle(color: Colors.white.withOpacity(0.4)),
                  ),
                )
              : ListView.builder(
                  itemCount: _clipboardItems.length,
                  itemBuilder: (context, index) {
                    final item = _clipboardItems[index];
                    return _ClipboardItemCard(
                      item: item,
                      onTap: () => _pasteItem(item),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _pasteItem(Map<String, dynamic> item) {
    debugPrint('Pasting: ${item['content']}');
    // TODO: Implement paste functionality
  }
}

class _ClipboardItemCard extends StatefulWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;

  const _ClipboardItemCard({
    required this.item,
    required this.onTap,
  });

  @override
  State<_ClipboardItemCard> createState() => _ClipboardItemCardState();
}

class _ClipboardItemCardState extends State<_ClipboardItemCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final String content = widget.item['content'] as String;
    final String type = widget.item['type'] as String;
    final int timestamp = widget.item['created_at'] as int;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _isHovered
                  ? Colors.white.withOpacity(0.08)
                  : Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _isHovered
                    ? Colors.white.withOpacity(0.12)
                    : Colors.white.withOpacity(0.06),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _getIconForType(type),
                      size: 16,
                      color: _getColorForType(type),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.item['source_app'] ?? 'Unknown',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _formatTimestamp(DateTime.fromMillisecondsSinceEpoch(timestamp)),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  content,
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
      ),
    );
  }

  IconData _getIconForType(String type) {
    switch (type) {
      case 'text':
        return Icons.text_fields;
      case 'image':
        return Icons.image;
      case 'file':
        return Icons.insert_drive_file;
      default:
        return Icons.content_paste;
    }
  }

  Color _getColorForType(String type) {
    switch (type) {
      case 'text':
        return const Color(0xFF64FFDA);
      case 'image':
        return const Color(0xFFFF7597);
      case 'file':
        return const Color(0xFF82AAFF);
      default:
        return Colors.white;
    }
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
