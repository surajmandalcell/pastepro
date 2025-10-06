import 'package:flutter_test/flutter_test.dart';
import 'package:pastepro/database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('ClipboardDatabase', () {
    test('should be a singleton', () {
      final instance1 = ClipboardDatabase.instance;
      final instance2 = ClipboardDatabase.instance;
      expect(identical(instance1, instance2), true);
    });

    test('database operations should not crash', () async {
      // Basic smoke test
      expect(() => ClipboardDatabase.instance.database, returnsNormally);
    });
  });
}
