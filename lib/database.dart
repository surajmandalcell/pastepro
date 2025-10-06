import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class ClipboardDatabase {
  static final ClipboardDatabase instance = ClipboardDatabase._init();
  static Database? _database;

  ClipboardDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('clipboard.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    if (Platform.isLinux || Platform.isWindows) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = await getApplicationDocumentsDirectory();
    final path = join(dbPath.path, 'pastepro', filePath);

    // Create directory if it doesn't exist
    await Directory(dirname(path)).create(recursive: true);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          await _createCategories(db);
          await _seedDefaultCategories(db);
        }
      },
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE clipboard_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        content TEXT NOT NULL,
        type TEXT NOT NULL,
        category TEXT,
        source_app TEXT,
        thumbnail_path TEXT,
        created_at INTEGER NOT NULL,
        is_favorite INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_created_at ON clipboard_items(created_at DESC)
    ''');

    await db.execute('''
      CREATE INDEX idx_category ON clipboard_items(category)
    ''');

    await _createCategories(db);
    await _seedDefaultCategories(db);
  }

  Future<void> _createCategories(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL,
        color INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _seedDefaultCategories(Database db) async {
    final defaults = [
      {'name': 'Clipboard History', 'color': 0xFFD7C6A5},
      {'name': 'Useful Links', 'color': 0xFFF16B5F},
      {'name': 'Important Notes', 'color': 0xFFF4C34A},
      {'name': 'Email Templates', 'color': 0xFF69D494},
      {'name': 'Code Snippets', 'color': 0xFF5AA7F8},
    ];
    for (final c in defaults) {
      try {
        await db.insert('categories', {
          'name': c['name'],
          'color': c['color'],
        });
      } catch (_) {
        // ignore duplicates
      }
    }
  }

  Future<int> insertItem(Map<String, dynamic> item) async {
    final db = await database;
    return await db.insert('clipboard_items', item);
  }

  Future<List<Map<String, dynamic>>> getItems({
    String? category,
    int limit = 100,
  }) async {
    final db = await database;
    if (category != null && category.isNotEmpty) {
      return await db.query(
        'clipboard_items',
        where: 'category = ?',
        whereArgs: [category],
        orderBy: 'created_at DESC',
        limit: limit,
      );
    }
    return await db.query(
      'clipboard_items',
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  Future<int> deleteItem(int id) async {
    final db = await database;
    return await db.delete(
      'clipboard_items',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> toggleFavorite(int id, bool isFavorite) async {
    final db = await database;
    return await db.update(
      'clipboard_items',
      {'is_favorite': isFavorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> setItemCategory(int id, String? category) async {
    final db = await database;
    return await db.update(
      'clipboard_items',
      {'category': category},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> getCategories() async {
    final db = await database;
    return await db.query('categories', orderBy: 'id ASC');
  }

  Future<int> insertCategory(String name, int color) async {
    final db = await database;
    return await db.insert('categories', {'name': name, 'color': color});
  }

  Future<int> deleteCategory(int id) async {
    final db = await database;
    return await db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearOldItems(int daysToKeep) async {
    final db = await database;
    final cutoffTime = DateTime.now()
        .subtract(Duration(days: daysToKeep))
        .millisecondsSinceEpoch;

    await db.delete(
      'clipboard_items',
      where: 'created_at < ? AND is_favorite = 0',
      whereArgs: [cutoffTime],
    );
  }

  Future close() async {
    final db = await database;
    db.close();
  }
}
