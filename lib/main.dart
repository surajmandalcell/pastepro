import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:window_manager/window_manager.dart';
// screen_retriever is used within WindowService; not needed here
import 'dart:ui';
import 'package:screen_retriever/screen_retriever.dart';

import 'models/clipboard_item.dart';
import 'models/category.dart' as m;
import 'database.dart';
import 'services/clipboard_service.dart';
import 'services/single_instance_manager.dart';
import 'services/window_service.dart';
import 'services/logging_service.dart';
import 'ui/app_theme.dart';
import 'settings_panel.dart';

const double _overlayHeightRatio = 0.60;
final HotKey _toggleHotKey = HotKey(
  key: PhysicalKeyboardKey.backslash,
  modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
  scope: HotKeyScope.system,
);

Future<void> main() async {
  // Wrap everything in error handling and capture prints to app.log
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await LoggingService.instance.initialize();
    FlutterError.onError = (details) {
      LoggingService.instance.error(details.exception, details.stack);
      FlutterError.presentError(details);
    };

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
    LoggingService.instance.error(error, stack);
  },
      zoneSpecification: LoggingService.instance.zoneSpec);
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
  final FocusNode _rootFocus = FocusNode();
  final ValueNotifier<ThemeMode> _themeMode = ValueNotifier(ThemeMode.system);

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
        if (_rootFocus.canRequestFocus) {
          _rootFocus.requestFocus();
        }
      }
    } catch (e) {
      debugPrint('Toggle error: $e');
    }
  }

  @override
  void onWindowBlur() {
    // Only hide when user actually clicked outside our bounds; don't hide on arbitrary focus loss.
    unawaited(_hideIfClickedOutside());
  }

  Future<void> _hideIfClickedOutside() async {
    try {
      final rect = await windowManager.getBounds();
      // Delay a bit so pointer position reflects the click event that caused blur.
      await Future.delayed(const Duration(milliseconds: 20));
      final p = await screenRetriever.getCursorScreenPoint();
      final inside = p.dx >= rect.left && p.dx <= rect.left + rect.width &&
          p.dy >= rect.top && p.dy <= rect.top + rect.height;
      if (!inside) {
        await _animationController.reverse();
        await WindowService.instance.hide();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final overlayHeight = WindowService.instance.overlayHeight ?? 480;

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeMode,
      builder: (_, mode, __) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PastePro',
      themeMode: mode,
      theme: ThemeData(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF64FFDA),
          secondary: Color(0xFF1F2933),
          surface: Color(0xFF0B0F14),
        ),
        scaffoldBackgroundColor: Colors.transparent,
        useMaterial3: true,
      ),
      darkTheme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: AnimatedBuilder(
          animation: _animationController,
          builder: (context, _) {
            return Align(
              alignment: Alignment.bottomCenter,
              child: Transform.translate(
                offset: Offset(0, (1 - _slideAnimation.value) * 40),
                child: Opacity(
                  opacity: _fadeAnimation.value,
                  child: _OverlayShell(
                    focusNode: _rootFocus,
                    overlayHeight: overlayHeight,
                    onDismiss: () async {
                      await _animationController.reverse();
                      await WindowService.instance.hide();
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ));
  }
}

class _OverlayContent extends StatefulWidget {
  const _OverlayContent();

  @override
  State<_OverlayContent> createState() => _OverlayContentState();
}

class _OverlayShell extends StatelessWidget {
  final FocusNode focusNode;
  final double overlayHeight;
  final Future<void> Function() onDismiss;
  const _OverlayShell({required this.focusNode, required this.overlayHeight, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.escape): const DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          DismissIntent: CallbackAction<DismissIntent>(onInvoke: (intent) {
            onDismiss();
            return null;
          }),
        },
        child: Focus(
          autofocus: true,
          focusNode: focusNode,
          child: Container(
            width: double.infinity,
            height: overlayHeight,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(kOverlayRadius)),
              border: Border.all(color: AppTheme.overlayBorder(context), width: 1),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.overlayShadow(context).withValues(alpha: kShadowOpacity),
                  blurRadius: kShadowBlur,
                  offset: const Offset(0, kShadowYOffset),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(color: AppTheme.overlayScrim(context)),
                BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: kBackdropBlurSigma, sigmaY: kBackdropBlurSigma),
                  child: const SizedBox.expand(),
                ),
                Container(color: AppTheme.overlayTint(context)),
                const Padding(
                  padding: EdgeInsets.fromLTRB(kOverlaySidePadding, kOverlayTopPadding, kOverlaySidePadding, 20),
                  child: _OverlayContent(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OverlayContentState extends State<_OverlayContent> with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late TabController _tabController;
  List<ClipboardItem> _clipboardItems = [];
  String _searchQuery = '';
  String _selectedCategory = 'Clipboard History';
  List<m.Category> _categories = [];

  @override
  void initState() {
    super.initState();
    _loadCategories().then((_) => _loadClipboardItems());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) {
      setState(() {
        _selectedCategory = _categories[_tabController.index].name;
      });
      _loadClipboardItems();
    }
  }

  Future<void> _loadClipboardItems() async {
    try {
      final items = await ClipboardService.instance.getItems(
        category: _selectedCategory == 'Clipboard History' ? null : _selectedCategory,
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
        // Top bar: [Search]  [Tags...]  [Settings]
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Search
            Expanded(
              flex: 3,
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.searchBg(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.searchBorder(context)),
                ),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  style: TextStyle(color: AppTheme.textPrimary(context), fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search...',
                    hintStyle: TextStyle(color: AppTheme.textTertiary(context)),
                    border: InputBorder.none,
                    isDense: true,
                    prefixIcon: Icon(Icons.search, size: 18, color: AppTheme.textTertiary(context)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  textAlignVertical: TextAlignVertical.center,
                  onChanged: (value) => setState(() => _searchQuery = value.trim().toLowerCase()),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Tags bar
            Expanded(
              flex: 5,
              child: _CategoryChips(
                categories: _categories,
                selected: _selectedCategory,
                onAdd: _addCategory,
                onDelete: _deleteCategory,
                onSelect: (name) {
                  setState(() => _selectedCategory = name);
                  _loadClipboardItems();
                },
                onAcceptDrop: (name, item) async {
                  if (item.id != null) {
                    await ClipboardService.instance.setItemCategory(item.id!, name);
                    await _loadClipboardItems();
                  }
                },
                onAddFromClipboard: (name) async {
                  await _addClipboardToCategory(name);
                },
              ),
            ),
            const SizedBox(width: 12),
            // Settings
            IconButton(
              tooltip: 'Settings',
              icon: Icon(Icons.settings_outlined, color: AppTheme.textPrimary(context)),
              onPressed: () {
                showDialog(
                  context: context,
                  barrierColor: Colors.black54,
                  builder: (_) => SettingsPanel(
                    themeMode: (context.findAncestorStateOfType<_PasteProAppState>()?._themeMode.value) ?? ThemeMode.system,
                    onThemeModeChanged: (m) => context.findAncestorStateOfType<_PasteProAppState>()?._themeMode.value = m,
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _filteredItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.content_paste, size: 64, color: AppTheme.textTertiary(context)),
                      const SizedBox(height: 16),
                      Text('No items yet', style: TextStyle(color: AppTheme.textSecondary(context), fontSize: 16)),
                      const SizedBox(height: 8),
                      Text('Copy something to get started', style: TextStyle(color: AppTheme.textTertiary(context), fontSize: 13)),
                    ],
                  ),
                )
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _filteredItems.length,
                  itemBuilder: (context, index) {
                    final item = _filteredItems[index];
                    return Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Draggable<ClipboardItem>(
                        data: item,
                        feedback: Material(
                          color: Colors.transparent,
                          child: Opacity(
                            opacity: 0.85,
                            child: SizedBox(width: 360, child: _ClipboardItemCard(item: item)),
                          ),
                        ),
                        child: SizedBox(width: 360, child: _ClipboardItemCard(item: item)),
                      ),
                    );
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

  Future<void> _addClipboardToCategory(String name) async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text == null || data!.text!.trim().isEmpty) return;
      final item = ClipboardItem(
        content: data.text!.trim(),
        type: 'text',
        category: name,
        sourceApp: 'Unknown',
        createdAt: DateTime.now(),
      );
      await ClipboardDatabase.instance.insertItem(item.toMap());
      await _loadClipboardItems();
    } catch (e) {
      LoggingService.instance.warn('Add from clipboard failed: $e');
    }
  }

  Future<void> _loadCategories() async {
    try {
      final rows = await ClipboardDatabase.instance.getCategories();
      final cats = rows.map((map) => m.Category.fromMap(map)).toList();
      setState(() {
        _categories = cats;
        if (cats.isNotEmpty) _selectedCategory = cats.first.name;
        _tabController = TabController(length: _categories.length, vsync: this);
        _tabController.addListener(_onTabChanged);
      });
    } catch (e) {
      LoggingService.instance.warn('loadCategories failed: $e');
    }
  }

  Future<void> _addCategory() async {
    final nameController = TextEditingController();
    final colorOptions = [0xFFD7C6A5, 0xFFF16B5F, 0xFFF4C34A, 0xFF69D494, 0xFF5AA7F8, 0xFFB48EDE];
    int picked = colorOptions.first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('New Category'),
        content: StatefulBuilder(builder: (context, setStateSB) {
          return Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameController, decoration: const InputDecoration(hintText: 'Name')),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              for (final col in colorOptions)
                InkWell(
                  onTap: () => setStateSB(() => picked = col),
                  child: Container(width: 24, height: 24, decoration: BoxDecoration(color: Color(col), shape: BoxShape.circle, border: Border.all(color: picked == col ? Colors.black : Colors.black26, width: picked == col ? 2 : 1))),
                ),
            ]),
          ]);
        }),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok == true) {
      await ClipboardDatabase.instance.insertCategory(nameController.text.trim(), picked);
      await _loadCategories();
    }
  }

  Future<void> _deleteCategory(m.Category cat) async {
    await ClipboardDatabase.instance.deleteCategory(cat.id);
    await _loadCategories();
  }
}

class _CategoryChips extends StatelessWidget {
  final List<m.Category> categories;
  final String selected;
  final VoidCallback onAdd;
  final void Function(m.Category) onDelete;
  final ValueChanged<String> onSelect;
  final Future<void> Function(String, ClipboardItem) onAcceptDrop;
  final Future<void> Function(String) onAddFromClipboard;

  const _CategoryChips({
    required this.categories,
    required this.selected,
    required this.onAdd,
    required this.onDelete,
    required this.onSelect,
    required this.onAcceptDrop,
    required this.onAddFromClipboard,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          const SizedBox(width: 6),
          for (final cat in categories)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: DragTarget<ClipboardItem>(
                onAcceptWithDetails: (details) => onAcceptDrop(cat.name, details.data),
                builder: (context, candidate, rejected) {
                  final selectedColor = Color(cat.color).withValues(alpha: 0.7);
                  final back = Color(cat.color).withValues(alpha: 0.35);
                  return GestureDetector(
                    onSecondaryTapDown: (d) async {
                      final res = await showMenu<String>(
                        context: context,
                        position: RelativeRect.fromLTRB(d.globalPosition.dx, d.globalPosition.dy, 0, 0),
                        items: const [
                          PopupMenuItem(value: 'add', child: Text('Add From Clipboard')),
                          PopupMenuItem(value: 'delete', child: Text('Delete Category')),
                        ],
                      );
                      if (res == 'delete') onDelete(cat);
                      if (res == 'add') await onAddFromClipboard(cat.name);
                    },
                    child: ChoiceChip(
                      selected: selected == cat.name,
                      onSelected: (_) => onSelect(cat.name),
                      label: Text(cat.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      backgroundColor: back,
                      selectedColor: selectedColor,
                    ),
                  );
                },
              ),
            ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Category',
            onPressed: onAdd,
          ),
        ],
      ),
    );
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
            color: _isHovered ? AppTheme.cardHoverBg(context) : AppTheme.cardBg(context),
            borderRadius: BorderRadius.circular(kCardRadius),
            border: Border.all(color: AppTheme.cardBorder(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.text_fields,
                    size: 16,
                    color: kAccentTeal,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.item.sourceApp ?? 'Unknown',
                    style: TextStyle(
                      color: AppTheme.textSecondary(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatTimestamp(widget.item.createdAt),
                    style: TextStyle(
                      color: AppTheme.textTertiary(context),
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
                style: TextStyle(color: AppTheme.textPrimary(context), fontSize: 14, height: 1.5),
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
