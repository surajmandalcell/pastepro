import 'dart:async';
import 'dart:io';

class LoggingService {
  LoggingService._();
  static final LoggingService instance = LoggingService._();

  IOSink? _sink;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final file = File('${Directory.current.path}/app.log');
      // Rotate if the file is too large (>5MB)
      if (await file.exists()) {
        final length = await file.length();
        if (length > 5 * 1024 * 1024) {
          final rotated = File('${file.path}.${DateTime.now().millisecondsSinceEpoch}.old');
          await file.rename(rotated.path);
        }
      }
      _sink = file.openWrite(mode: FileMode.append);
      _initialized = true;
      log('Logging initialized at ${file.path}');
    } catch (_) {
      // If logging setup fails, we don't crash the app.
    }
  }

  void log(String message) {
    final ts = DateTime.now().toIso8601String();
    _sink?.writeln('[$ts] $message');
  }

  void info(String message) => log('INFO  $message');
  void warn(String message) => log('WARN  $message');
  void error(Object e, [StackTrace? st]) => log('ERROR $e\n${st ?? StackTrace.current}');

  Future<void> dispose() async {
      await _sink?.flush();
      await _sink?.close();
      _sink = null;
  }

  ZoneSpecification get zoneSpec => ZoneSpecification(
        print: (self, parent, zone, line) {
          log(line);
          parent.print(zone, line);
        },
      );
}

