import 'package:flutter_test/flutter_test.dart';
import 'package:pastepro/models/clipboard_item.dart';

void main() {
  group('ClipboardItem', () {
    test('should create item with required fields', () {
      final now = DateTime.now();
      final item = ClipboardItem(
        content: 'test content',
        type: 'text',
        createdAt: now,
      );

      expect(item.content, 'test content');
      expect(item.type, 'text');
      expect(item.createdAt, now);
      expect(item.isFavorite, false);
    });

    test('should convert to map correctly', () {
      final now = DateTime.now();
      final item = ClipboardItem(
        id: 1,
        content: 'test',
        type: 'text',
        category: 'links',
        sourceApp: 'Firefox',
        createdAt: now,
        isFavorite: true,
      );

      final map = item.toMap();

      expect(map['id'], 1);
      expect(map['content'], 'test');
      expect(map['type'], 'text');
      expect(map['category'], 'links');
      expect(map['source_app'], 'Firefox');
      expect(map['created_at'], now.millisecondsSinceEpoch);
      expect(map['is_favorite'], 1);
    });

    test('should create from map correctly', () {
      final now = DateTime.now();
      final map = {
        'id': 1,
        'content': 'test',
        'type': 'text',
        'category': 'links',
        'source_app': 'Firefox',
        'created_at': now.millisecondsSinceEpoch,
        'is_favorite': 1,
      };

      final item = ClipboardItem.fromMap(map);

      expect(item.id, 1);
      expect(item.content, 'test');
      expect(item.type, 'text');
      expect(item.category, 'links');
      expect(item.sourceApp, 'Firefox');
      expect(item.createdAt.millisecondsSinceEpoch, now.millisecondsSinceEpoch);
      expect(item.isFavorite, true);
    });

    test('should handle isFavorite conversion', () {
      final map1 = {
        'content': 'test',
        'type': 'text',
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'is_favorite': 0,
      };

      final item1 = ClipboardItem.fromMap(map1);
      expect(item1.isFavorite, false);

      final map2 = {
        'content': 'test',
        'type': 'text',
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'is_favorite': 1,
      };

      final item2 = ClipboardItem.fromMap(map2);
      expect(item2.isFavorite, true);
    });

    test('should copy with new values', () {
      final now = DateTime.now();
      final item = ClipboardItem(
        id: 1,
        content: 'original',
        type: 'text',
        createdAt: now,
      );

      final copied = item.copyWith(content: 'modified', isFavorite: true);

      expect(copied.id, 1);
      expect(copied.content, 'modified');
      expect(copied.type, 'text');
      expect(copied.createdAt, now);
      expect(copied.isFavorite, true);
    });
  });
}
