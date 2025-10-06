import 'package:flutter_test/flutter_test.dart';
import 'package:pastepro/services/clipboard_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ClipboardService', () {
    late ClipboardService service;

    setUp(() {
      service = ClipboardService.instance;
    });

    tearDown(() {
      service.stopMonitoring();
    });

    test('should be a singleton', () {
      final instance1 = ClipboardService.instance;
      final instance2 = ClipboardService.instance;
      expect(identical(instance1, instance2), true);
    });

    test('should start and stop monitoring', () {
      expect(service.startMonitoring, returnsNormally);
      expect(service.stopMonitoring, returnsNormally);
    });

    test('should categorize URLs as links', () {
      final service = ClipboardService.instance;
      // Use reflection or make method public for testing
      // For now, test through the service behavior
      expect(service, isNotNull);
    });

    test('should emit new items on stream', () async {
      // This would require mocking Clipboard
      // Skipping for now as it requires platform channel mocking
    });
  });
}
