import 'dart:async';

class GrpcChannel {
  final String socketPath;
  bool _connected = false;
  final StreamController<bool> _connectionStateController = StreamController<bool>.broadcast();

  GrpcChannel({required this.socketPath});

  /// Checks if the channel is currently connected.
  bool get isConnected => _connected;

  /// Emits updates whenever the connection state changes.
  Stream<bool> get connectionStateChanges => _connectionStateController.stream;

  /// Connects or simulates connection over the Unix Domain Socket (UDS).
  Future<bool> connect({bool simulateFailure = false}) async {
    // Simulate connection delay for initialization
    await Future.delayed(const Duration(milliseconds: 100));
    if (simulateFailure) {
      _connected = false;
      _connectionStateController.add(false);
      return false;
    }
    _connected = true;
    _connectionStateController.add(true);
    return true;
  }

  /// Triggers a simulated disconnection/fault state.
  void disconnect() {
    _connected = false;
    _connectionStateController.add(false);
  }

  /// Disposes of the connection state stream.
  void dispose() {
    _connectionStateController.close();
  }
}
