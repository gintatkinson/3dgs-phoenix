import 'dart:io';

class ProcessExecutor {
  final Future<Process> Function(String, List<String>, {required ProcessStartMode mode})? _spawn;

  ProcessExecutor({
    Future<Process> Function(String, List<String>, {required ProcessStartMode mode})? spawn,
  }) : _spawn = spawn;

  /// Spawns an independent sub-process running the given [executable] with [args].
  /// Spawns the process using [ProcessStartMode.detached] to ensure that it runs
  /// independently of the parent process. Returns true if the process is successfully
  /// started, or false otherwise.
  Future<bool> startProcess(String executable, List<String> args) async {
    try {
      if (_spawn != null) {
        await _spawn!(executable, args, mode: ProcessStartMode.detached);
      } else {
        await Process.start(executable, args, mode: ProcessStartMode.detached);
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
