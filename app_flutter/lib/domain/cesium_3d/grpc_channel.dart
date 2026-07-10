import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

typedef GrpcChannel = DaemonClient;

class IosurfaceUpdate {
  final int? textureId;
  IosurfaceUpdate({this.textureId});
}

class DaemonClient {
  final String socketPath;
  static const Duration _connectTimeout = Duration(seconds: 5);

  Socket? _socket;
  bool _connected = false;
  bool _disposed = false;
  int? _latestIosurfaceId;

  final StringBuffer _buffer = StringBuffer();
  Completer<Map<String, dynamic>?>? _responseCompleter;
  Timer? _responseTimer;

  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  bool _intentionalDisconnect = false;
  static final Duration _maxBackoff = const Duration(seconds: 5);
  static final Duration _initialBackoff = const Duration(seconds: 1);

  final StreamController<bool> _connectionStateController = StreamController<bool>.broadcast();
  final StreamController<IosurfaceUpdate> _iosurfaceController = StreamController<IosurfaceUpdate>.broadcast();
  final StreamController<String> _responseController = StreamController<String>.broadcast();

  bool get isConnected => _connected;

  Stream<bool> get connectionStateChanges => _connectionStateController.stream;

  Stream<IosurfaceUpdate> get iosurfaceUpdates => _iosurfaceController.stream;

  Stream<String> get responses => _responseController.stream;

  int? get latestIosurfaceId => _latestIosurfaceId;

  DaemonClient({required this.socketPath});

  Future<bool> connect() async {
    _intentionalDisconnect = false;
    try {
      _socket = await Socket.connect(
        InternetAddress(socketPath, type: InternetAddressType.unix),
        0,
        timeout: _connectTimeout,
      );

      _connected = true;
      _reconnectAttempts = 0;
      if (!_connectionStateController.isClosed) {
        _connectionStateController.add(true);
      }

      _buffer.clear();
      _socket!.listen(
        _onData,
        onError: _onSocketError,
        onDone: _onSocketDone,
        cancelOnError: false,
      );

      _sendRaw({'type': 'health_check'});
      return true;
    } catch (_) {
      _connected = false;
      if (!_connectionStateController.isClosed) {
        _connectionStateController.add(false);
      }
      _scheduleReconnect();
      return false;
    }
  }

  void disconnect() {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _responseTimer?.cancel();
    _responseCompleter?.complete(null);
    _responseCompleter = null;
    _buffer.clear();
    _socket?.destroy();
    _socket = null;
    _connected = false;
    if (!_connectionStateController.isClosed) {
      _connectionStateController.add(false);
    }
  }

  void dispose() {
    _disposed = true;
    disconnect();
    _connectionStateController.close();
    _iosurfaceController.close();
    _responseController.close();
  }

  void sendCommand(Map<String, dynamic> json) {
    _sendRaw(json);
  }

  Future<bool> sendCameraUpdate({
    required double lat,
    required double lon,
    required double alt,
    required double heading,
    required double pitch,
    required double roll,
  }) async {
    _sendRaw({
      'type': 'update_camera',
      'lat': lat,
      'lon': lon,
      'alt': alt,
      'heading': heading,
      'pitch': pitch,
      'roll': roll,
    });
    return _connected;
  }

  Future<String?> getIosurfaceId() async {
    final result = await _sendAndWait({'type': 'get_iosurface_id'});
    return result?['id']?.toString() ?? _latestIosurfaceId?.toString();
  }

  Future<bool> healthCheck() async {
    final result = await _sendAndWait({'type': 'health_check'});
    return result != null && result['status'] == 'ok';
  }

  void _sendRaw(Map<String, dynamic> msg) {
    if (!_connected || _socket == null) return;
    try {
      _socket!.write('${jsonEncode(msg)}\n');
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _sendAndWait(Map<String, dynamic> msg) async {
    if (!_connected || _socket == null) return null;

    final completer = Completer<Map<String, dynamic>?>();
    _responseCompleter = completer;
    _responseTimer?.cancel();
    _responseTimer = Timer(const Duration(seconds: 2), () {
      if (!completer.isCompleted) completer.complete(null);
    });

    try {
      _socket!.write('${jsonEncode(msg)}\n');
    } catch (_) {
      _responseTimer?.cancel();
      _responseCompleter = null;
      return null;
    }

    try {
      return await completer.future;
    } catch (_) {
      return null;
    }
  }

  void _onData(Uint8List data) {
    _buffer.write(utf8.decode(data, allowMalformed: true));
    _processBuffer();
  }

  void _processBuffer() {
    final raw = _buffer.toString();
    _buffer.clear();

    int start = 0;
    for (int i = 0; i < raw.length; i++) {
      if (raw[i] == '\n') {
        final line = raw.substring(start, i).trim();
        start = i + 1;
        if (line.isEmpty) continue;
        if (!_responseController.isClosed) {
          _responseController.add(line);
        }
        try {
          final json = jsonDecode(line) as Map<String, dynamic>;
          _handleMessage(json);
        } catch (_) {}
      }
    }

    if (start < raw.length) {
      _buffer.write(raw.substring(start));
    }
  }

  void _handleMessage(Map<String, dynamic> msg) {
    final type = msg['type'] as String?;

    if (type == 'iosurface_id') {
      final id = msg['id'] as int?;
      if (id != null) {
        _latestIosurfaceId = id;
        if (!_iosurfaceController.isClosed) {
          _iosurfaceController.add(IosurfaceUpdate(textureId: id));
        }
      }
    }

    if (_responseCompleter != null && !_responseCompleter!.isCompleted) {
      _responseTimer?.cancel();
      _responseCompleter!.complete(msg);
      _responseCompleter = null;
    }
  }

  void _onSocketError(dynamic _) {
    _handleDisconnection();
  }

  void _onSocketDone() {
    _handleDisconnection();
  }

  void _handleDisconnection() {
    _socket?.destroy();
    _socket = null;
    _connected = false;
    _buffer.clear();
    _responseTimer?.cancel();
    _responseCompleter?.complete(null);
    _responseCompleter = null;
    if (!_connectionStateController.isClosed) {
      _connectionStateController.add(false);
    }
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_intentionalDisconnect || _disposed) return;
    _reconnectTimer?.cancel();
    final backoff = _initialBackoff * pow(2, _reconnectAttempts) > _maxBackoff
        ? _maxBackoff
        : _initialBackoff * pow(2, _reconnectAttempts);
    _reconnectAttempts++;
    _reconnectTimer = Timer(backoff, () {
      connect();
    });
  }
}
