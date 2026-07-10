import 'package:flutter_test/flutter_test.dart';
import 'package:app_flutter/domain/cesium_3d/grpc_channel.dart';

void main() {
  group('DaemonClient disconnect robustness', () {
    test('disconnect does not throw when called after dispose', () {
      final client = DaemonClient(socketPath: '/tmp/test_disconnect.sock');
      client.dispose(); // closes stream controllers
      // Should not throw
      client.disconnect();
    });

    test('disconnect can be called twice without crash', () async {
      final client = DaemonClient(socketPath: '/tmp/test_disconnect.sock');
      client.disconnect();
      // Second disconnect should not throw
      client.disconnect();
      client.dispose();
    });
  });
}
