import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class SingleInstanceManager {
  static final SingleInstanceManager instance = SingleInstanceManager._();
  SingleInstanceManager._();

  File? _lockFile;

  /// Ensures only one instance runs. Returns true if this is the only instance.
  Future<bool> ensureSingleInstance() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _lockFile = File(path.join(appDir.path, 'pastepro', '.lock'));

      if (await _lockFile!.exists()) {
        final pidStr = await _lockFile!.readAsString();
        final pid = int.tryParse(pidStr.trim());

        if (pid != null && _isProcessRunning(pid)) {
          await _killProcess(pid);
          await Future.delayed(const Duration(milliseconds: 500));
        }

        await _lockFile!.delete();
      }

      await _lockFile!.parent.create(recursive: true);
      final maybePid = _currentPid();
      await _lockFile!.writeAsString(maybePid?.toString() ?? 'PID:dev');

      return true;
    } catch (e) {
      print('SingleInstanceManager error: $e');
      return true; // Continue anyway
    }
  }

  int? _currentPid() {
    try {
      // Works on Linux: first token of /proc/self/stat is the pid
      final stat = File('/proc/self/stat');
      if (stat.existsSync()) {
        final content = stat.readAsStringSync();
        final pidStr = content.split(' ').first;
        return int.tryParse(pidStr);
      }
    } catch (_) {}
    return null;
  }

  bool _isProcessRunning(int pid) {
    try {
      final result = Process.runSync('kill', ['-0', pid.toString()]);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  Future<void> _killProcess(int pid) async {
    try {
      await Process.run('kill', [pid.toString()]);
    } catch (e) {
      print('Failed to kill process $pid: $e');
    }
  }

  Future<void> cleanup() async {
    try {
      if (_lockFile != null && await _lockFile!.exists()) {
        await _lockFile!.delete();
      }
    } catch (e) {
      print('Failed to cleanup lock file: $e');
    }
  }
}
