import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_flutter/domain/cesium_3d/unreal_daemon_manager.dart';

class FakeProcess extends Fake implements Process {
  final Completer<int> _exitCodeCompleter = Completer<int>();
  bool _isKilled = false;

  @override
  Future<int> get exitCode => _exitCodeCompleter.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    _isKilled = true;
    if (!_exitCodeCompleter.isCompleted) {
      _exitCodeCompleter.complete(-1);
    }
    return true;
  }

  void simulateExit(int code) {
    if (!_exitCodeCompleter.isCompleted) {
      _exitCodeCompleter.complete(code);
    }
  }

  bool get isKilled => _isKilled;
}

void main() {
  group('UnrealDaemonManager Tests', () {
    test('spawnDaemon starts process with -RenderOffscreen flag', () async {
      String? spawnedPath;
      List<String>? spawnedArgs;

      final manager = UnrealDaemonManager(
        fileExists: (path) => path == '/valid/path/to/unreal',
        spawnProcess: (path, args) async {
          spawnedPath = path;
          spawnedArgs = args;
          return FakeProcess();
        },
      );

      final result = await manager.spawnDaemon('/valid/path/to/unreal');
      expect(result, isTrue);
      expect(spawnedPath, equals('/valid/path/to/unreal'));
      expect(spawnedArgs![0], equals('-RenderOffscreen'));
      expect(spawnedArgs![1], startsWith('-SavedDir='));
    });

    test('spawnDaemon throws DaemonBootFailure on invalid paths', () async {
      final manager = UnrealDaemonManager(
        fileExists: (path) => false,
      );

      expect(
        () => manager.spawnDaemon('/invalid/path'),
        throwsA(isA<DaemonBootFailure>()),
      );
    });

    test('spawnDaemon throws DaemonBootFailure if process spawning fails', () async {
      final manager = UnrealDaemonManager(
        fileExists: (path) => true,
        spawnProcess: (path, args) async {
          throw Exception('OS Error: Permission denied');
        },
      );

      expect(
        () => manager.spawnDaemon('/valid/path'),
        throwsA(isA<DaemonBootFailure>()),
      );
    });

    test('monitorDaemon recovers and restarts daemon on abnormal exit', () async {
      final List<FakeProcess> processes = [];
      final List<List<String>> spawnArgsHistory = [];

      final manager = UnrealDaemonManager(
        fileExists: (path) => true,
        spawnProcess: (path, args) async {
          spawnArgsHistory.add(args);
          final proc = FakeProcess();
          processes.add(proc);
          return proc;
        },
      );

      // Start the daemon
      await manager.spawnDaemon('/valid/path');
      expect(processes.length, equals(1));

      // Start monitoring in a Future so we can control exit codes
      final monitorFuture = manager.monitorDaemon();

      // Simulate first process crashing (exit code 139 - Segmentation fault)
      processes[0].simulateExit(139);

      // Allow event loop to run recovery
      await Future.delayed(const Duration(milliseconds: 10));

      // A second process should have been spawned
      expect(processes.length, equals(2));
      expect(spawnArgsHistory[1][0], equals('-RenderOffscreen'));
      expect(spawnArgsHistory[1][1], startsWith('-SavedDir='));

      // Simulate second process exiting normally (exit code 0)
      processes[1].simulateExit(0);

      // Monitor should complete with true
      final monitorResult = await monitorFuture;
      expect(monitorResult, isTrue);
    });

    test('restart loop halts and throws MaxRebootThresholdReached if crashes continuously exceed the limit', () async {
      final List<FakeProcess> processes = [];

      final manager = UnrealDaemonManager(
        fileExists: (path) => true,
        maxReboots: 2, // Allow up to 2 reboots (3 crashes total)
        thresholdWindow: const Duration(seconds: 5),
        spawnProcess: (path, args) async {
          final proc = FakeProcess();
          processes.add(proc);
          return proc;
        },
      );

      // 1. Initial spawn (Process 0)
      await manager.spawnDaemon('/valid/path');
      expect(processes.length, equals(1));

      final monitorFuture = manager.monitorDaemon();

      // 2. Process 0 crashes (1st crash) -> triggers 1st reboot (spawns Process 1)
      processes[0].simulateExit(139);
      await Future.delayed(const Duration(milliseconds: 10));
      expect(processes.length, equals(2));

      // 3. Process 1 crashes (2nd crash) -> triggers 2nd reboot (spawns Process 2)
      processes[1].simulateExit(139);
      await Future.delayed(const Duration(milliseconds: 10));
      expect(processes.length, equals(3));

      // 4. Process 2 crashes (3rd crash) -> exceeds limit of 2 reboots -> throws MaxRebootThresholdReached
      processes[2].simulateExit(139);

      // Monitor future should complete with error
      expect(
        () => monitorFuture,
        throwsA(isA<MaxRebootThresholdReached>()),
      );
    });

    test('spawnDaemon passes -SceneId= arg when sceneId is provided', () async {
      List<String>? spawnedArgs;

      final manager = UnrealDaemonManager(
        fileExists: (path) => path == '/valid/path',
        spawnProcess: (path, args) async {
          spawnedArgs = args;
          return FakeProcess();
        },
      );

      await manager.spawnDaemon('/valid/path', sceneId: 'test');
      expect(spawnedArgs!.any((arg) => arg == '-SceneId=test'), isTrue);
    });

    test('restartDaemon kills existing process and spawns new one', () async {
      final List<FakeProcess> processes = [];

      final manager = UnrealDaemonManager(
        fileExists: (path) => true,
        spawnProcess: (path, args) async {
          final proc = FakeProcess();
          processes.add(proc);
          return proc;
        },
      );

      await manager.spawnDaemon('/valid/path');
      expect(processes.length, equals(1));
      expect(processes[0].isKilled, isFalse);

      final restarted = await manager.restartDaemon();
      expect(restarted, isTrue);
      expect(processes.length, equals(2));
      expect(processes[0].isKilled, isTrue);
      expect(processes[1].isKilled, isFalse);
    });
  });
}
