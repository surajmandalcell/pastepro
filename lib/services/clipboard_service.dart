import 'dart:async';
import 'package:flutter/services.dart';
import '../database.dart';
import '../models/clipboard_item.dart';

class ClipboardService {
  static final ClipboardService instance = ClipboardService._();
  ClipboardService._();

  Timer? _monitorTimer;
  String? _lastContent;
  final StreamController<ClipboardItem> _itemController = StreamController.broadcast();

  Stream<ClipboardItem> get onNewItem => _itemController.stream;

  void startMonitoring({Duration interval = const Duration(seconds: 2)}) {
    _monitorTimer?.cancel();
    _monitorTimer = Timer.periodic(interval, (_) => _checkClipboard());
  }

  void stopMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
  }

  Future<void> _checkClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text != null && data!.text!.isNotEmpty) {
        final content = data.text!;

        // Avoid duplicates
        if (content == _lastContent) return;
        _lastContent = content;

        final item = ClipboardItem(
          content: content,
          type: 'text',
          category: _categorizeContent(content),
          sourceApp: 'Unknown',
          createdAt: DateTime.now(),
        );

        await _saveItem(item);
        _itemController.add(item);
      }
    } catch (e) {
      // Clipboard access can fail, ignore
    }
  }

  String _categorizeContent(String content) {
    if (content.startsWith('http://') || content.startsWith('https://')) {
      return 'links';
    } else if (content.contains(RegExp(r'\b(struct|function|class|def|const|var|let)\b'))) {
      return 'code';
    } else if (content.length > 200) {
      return 'notes';
    }
    return 'history';
  }

  Future<void> _saveItem(ClipboardItem item) async {
    try {
      await ClipboardDatabase.instance.insertItem(item.toMap());
    } catch (e) {
      print('Failed to save clipboard item: $e');
    }
  }

  Future<List<ClipboardItem>> getItems({String? category, int limit = 100}) async {
    try {
      final maps = await ClipboardDatabase.instance.getItems(
        category: category,
        limit: limit,
      );
      return maps.map((map) => ClipboardItem.fromMap(map)).toList();
    } catch (e) {
      print('Failed to get clipboard items: $e');
      return [];
    }
  }

  Future<void> setItemCategory(int id, String? category) async {
    try {
      await ClipboardDatabase.instance.setItemCategory(id, category);
    } catch (e) {
      print('Failed to set item category: $e');
    }
  }

  Future<void> deleteItem(int id) async {
    try {
      await ClipboardDatabase.instance.deleteItem(id);
    } catch (e) {
      print('Failed to delete item: $e');
    }
  }

  void dispose() {
    stopMonitoring();
    _itemController.close();
  }
}
