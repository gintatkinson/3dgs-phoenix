import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'grpc_channel.dart';

/// Exception thrown when the Unreal daemon fails to start or the executable path is invalid.
class DaemonBootFailure implements Exception {
  final String message;
  DaemonBootFailure(this.message);

  @override
  String toString() => 'DaemonBootFailure: $message';
}

/// Exception thrown when the number of automatic reboots within the threshold window exceeds the limit.
class MaxRebootThresholdReached implements Exception {
  final String message;
  MaxRebootThresholdReached(this.message);

  @override
  String toString() => 'MaxRebootThresholdReached: $message';
}

/// A watcher class to monitor the exit code of an OS process.
class ProcessWatcher {
  final Process _process;

  ProcessWatcher(this._process);

  /// Monitors and returns the exit code when the process terminates.
  Future<int> watchExitCode() {
    return _process.exitCode;
  }
}

/// Manages the lifecycle of the headless Unreal rendering daemon.
class UnrealDaemonManager {
  final Future<Process> Function(String, List<String>) _spawnProcess;
  final bool Function(String) _fileExists;
  final void Function(String)? _log;

  Process? _process;
  ProcessWatcher? _watcher;
  String? _unrealPath;
  String? _sceneId;
  DaemonClient? _client;

  final List<DateTime> _crashTimes = [];
  final int maxReboots;
  final Duration thresholdWindow;

  VoidCallback? onProcessExit;

  /// Gets the Unix Domain Socket path for the daemon.
  String? get socketPath => _sceneId != null ? '/tmp/cesium_daemon_$_sceneId.sock' : null;

  /// The scene ID used to construct the socket path.
  String? get sceneId => _sceneId;

  /// The connected [DaemonClient] for UDS communication with the daemon.
  DaemonClient? get client => _client;

  /// Creates a new [UnrealDaemonManager].
  ///
  /// Can optionally inject custom [spawnProcess], [fileExists] functions for testing,
  /// and a [sceneId] for determining the socket path.
  UnrealDaemonManager({
    Future<Process> Function(String, List<String>)? spawnProcess,
    bool Function(String)? fileExists,
    void Function(String)? log,
    String? sceneId,
    this.maxReboots = 3,
    this.thresholdWindow = const Duration(seconds: 60),
  })  : _sceneId = sceneId,
        _spawnProcess = spawnProcess ?? _defaultSpawn,
        _fileExists = fileExists ?? _defaultFileExists,
        _log = log;

  static Future<Process> _defaultSpawn(String path, List<String> args) {
    return Process.start(path, args);
  }

  static bool _defaultFileExists(String path) {
    return File(path).existsSync();
  }

  /// Gets the currently running process, if any.
  Process? get activeProcess => _process;

  /// Gets the active watcher, if any.
  ProcessWatcher? get activeWatcher => _watcher;

  String? _workingDirectory;

  /// Starts the Unreal rendering daemon with the `-RenderOffscreen` flag.
  ///
  /// Throws [DaemonBootFailure] if the file doesn't exist or starting fails.
  /// If [sceneId] is provided, a [DaemonClient] will be created and connected
  /// automatically after successful spawn.
  Future<bool> spawnDaemon(String unrealPath, {String? workingDirectory, String? sceneId}) async {
    if (!_fileExists(unrealPath)) {
      throw DaemonBootFailure('Unreal executable file does not exist at path: $unrealPath');
    }

    if (sceneId != null) {
      _sceneId = sceneId;
    }

    _unrealPath = unrealPath;
    _workingDirectory = workingDirectory;

    try {
      _log?.call('Spawning Unreal daemon: $unrealPath with -RenderOffscreen');
      final savedPath = '${Directory.systemTemp.path}/cesium_daemon_saved';
      try {
        Directory(savedPath).createSync(recursive: true);
      } catch (_) {}
      
      final args = <String>['-RenderOffscreen', '-SavedDir=$savedPath'];
      if (_sceneId != null) {
        args.add('-SceneId=$_sceneId');
      }

      final Process process;
      if (workingDirectory != null && _spawnProcess == _defaultSpawn) {
        process = await Process.start(
          unrealPath,
          args,
          workingDirectory: workingDirectory,
        );
      } else {
        process = await _spawnProcess(unrealPath, args);
      }
      _process = process;
      _watcher = ProcessWatcher(process);

      if (_sceneId != null) {
        _client?.dispose();
        _client = DaemonClient(socketPath: socketPath!);
        _client!.connect();
      }

      return true;
    } catch (e) {
      throw DaemonBootFailure('Failed to start Unreal daemon process: $e');
    }
  }

  /// Registers process watchers and handles crashes.
  ///
  /// If the process exits abnormally (non-zero exit code), it logs and restarts
  /// the daemon, unless the crash threshold is exceeded, in which case it throws
  /// [MaxRebootThresholdReached] and halts.
  Future<bool> monitorDaemon() async {
    final watcher = _watcher;
    if (watcher == null) {
      _log?.call('No active daemon process to monitor.');
      return false;
    }

    try {
      final exitCode = await watcher.watchExitCode();
      onProcessExit?.call();
      if (exitCode == 0) {
        _log?.call('Unreal daemon process exited normally with code 0.');
        return true;
      } else {
        _log?.call('Unreal daemon process exited abnormally with code $exitCode.');

        final now = DateTime.now();
        _crashTimes.add(now);

        // Filter out crashes older than the threshold window
        final cutOff = now.subtract(thresholdWindow);
        _crashTimes.removeWhere((time) => time.isBefore(cutOff));

        if (_crashTimes.length > maxReboots) {
          throw MaxRebootThresholdReached(
            'Max reboot threshold ($maxReboots) reached within ${thresholdWindow.inSeconds} seconds. Halting auto-reboot.'
          );
        }

        _log?.call('Automatically recovering daemon process...');
        await restartDaemon();
        return await monitorDaemon();
      }
    } on MaxRebootThresholdReached {
      rethrow;
    } catch (e) {
      _log?.call('Error encountered during daemon monitoring: $e');
      rethrow;
    }
  }

  /// Kills any existing daemon process and respawns a new one.
  Future<bool> restartDaemon() async {
    final path = _unrealPath;
    if (path == null) {
      throw StateError('Cannot restart daemon: no path configured. Call spawnDaemon first.');
    }

    final active = _process;
    if (active != null) {
      _log?.call('Killing active daemon process.');
      _client?.disconnect();
      active.kill();
      _process = null;
      _watcher = null;
    }

    return await spawnDaemon(path, workingDirectory: _workingDirectory);
  }
}
