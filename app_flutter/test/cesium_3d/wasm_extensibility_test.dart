import 'package:flutter_test/flutter_test.dart';
import 'package:app_flutter/domain/cesium_3d/wasm/wasm_extensibility.dart';

void main() {
  group('WasmtimeEngine Tests', () {
    late WasmtimeEngine engine;

    setUp(() {
      engine = WasmtimeEngine();
    });

    test('initializeEngine returns true', () {
      expect(engine.initializeEngine(), isTrue);
    });

    test('loadWasmModule with empty path returns false', () {
      expect(engine.loadWasmModule(''), isFalse);
    });

    test('loadWasmModule with valid .wasm file returns true', () {
      expect(engine.loadWasmModule('plugin.wasm'), isTrue);
    });

    test('loadWasmModule with invalid file extension throws WitInterfaceMismatch', () {
      expect(
        () => engine.loadWasmModule('plugin.txt'),
        throwsA(isA<WitInterfaceMismatch>()),
      );
    });
  });

  group('WasiConfigurator Tests', () {
    late WasiConfigurator configurator;

    setUp(() {
      configurator = WasiConfigurator();
    });

    test('configureWasi allows directories starting with /tmp', () {
      expect(
        configurator.configureWasi(['/tmp/dir1', '/tmp/dir2/sub'], false),
        isTrue,
      );
    });

    test('configureWasi throws WasiSandboxViolation for directories outside /tmp', () {
      expect(
        () => configurator.configureWasi(['/tmp/dir1', '/usr/bin'], false),
        throwsA(isA<WasiSandboxViolation>()),
      );
    });
  });

  group('WitMarshaller Tests', () {
    late WitMarshaller marshaller;

    setUp(() {
      marshaller = WitMarshaller();
    });

    test('marshalRecord and unmarshalRecord roundtrip', () {
      const original = 'Hello, Wasm Extensibility Subsystem!';
      final bytes = marshaller.marshalRecord(original);
      final decoded = marshaller.unmarshalRecord(bytes);
      expect(decoded, original);
    });
  });

  group('AsynchronousBatcher Tests (Scenario 2)', () {
    late AsynchronousBatcher batcher;

    setUp(() {
      batcher = AsynchronousBatcher();
    });

    test('enqueuing multiple commands and clearing them on flushBatch()', () {
      expect(batcher.enqueueCommand('cmd1'), isTrue);
      expect(batcher.enqueueCommand('cmd2'), isTrue);
      expect(batcher.enqueueCommand('cmd3'), isTrue);

      expect(batcher.batchQueue, equals(['cmd1', 'cmd2', 'cmd3']));

      batcher.flushBatch();
      expect(batcher.batchQueue, isEmpty);
    });
  });

  group('Payload Validation Tests', () {
    test('Valid payload returns true', () {
      final payload = {
        'modulePath': 'test_plugin.wasm',
        'commands': ['run', 'execute'],
        'wasiAllowedDirs': ['/tmp/sandboxed'],
        'allowNetwork': false,
      };
      expect(validatePayload(payload), isTrue);
    });

    test('Lacking modulePath or commands throws WitInterfaceMismatch', () {
      final payloadNoModule = {
        'commands': ['run'],
      };
      expect(
        () => validatePayload(payloadNoModule),
        throwsA(isA<WitInterfaceMismatch>()),
      );

      final payloadNoCommands = {
        'modulePath': 'plugin.wasm',
      };
      expect(
        () => validatePayload(payloadNoCommands),
        throwsA(isA<WitInterfaceMismatch>()),
      );
    });

    test('Directory outside /tmp in wasiAllowedDirs throws WasiSandboxViolation', () {
      final payloadInvalidDir = {
        'modulePath': 'plugin.wasm',
        'commands': ['run'],
        'wasiAllowedDirs': ['/tmp/valid', '/home/user'],
        'allowNetwork': false,
      };
      expect(
        () => validatePayload(payloadInvalidDir),
        throwsA(isA<WasiSandboxViolation>()),
      );
    });

    test('Restricting network capability throws WasiSandboxViolation when allowNetwork is false and network key is present (Scenario 3)', () {
      final payloadWithNetworkKey = {
        'modulePath': 'plugin.wasm',
        'commands': ['run'],
        'wasiAllowedDirs': ['/tmp/valid'],
        'allowNetwork': false,
        'network': true,
      };
      expect(
        () => validatePayload(payloadWithNetworkKey),
        throwsA(isA<WasiSandboxViolation>()),
      );
    });

    test('Restricting network capability throws WasiSandboxViolation when allowNetwork is false and network command flag is simulated (Scenario 3)', () {
      final payloadWithNetworkCmd = {
        'modulePath': 'plugin.wasm',
        'commands': ['connect --network=true'],
        'wasiAllowedDirs': ['/tmp/valid'],
        'allowNetwork': false,
      };
      expect(
        () => validatePayload(payloadWithNetworkCmd),
        throwsA(isA<WasiSandboxViolation>()),
      );

      final payloadWithNetCmd = {
        'modulePath': 'plugin.wasm',
        'commands': ['sync -net'],
        'wasiAllowedDirs': ['/tmp/valid'],
        'allowNetwork': false,
      };
      expect(
        () => validatePayload(payloadWithNetCmd),
        throwsA(isA<WasiSandboxViolation>()),
      );
    });

    test('Allowing network does not throw WasiSandboxViolation even if network key or flag is present', () {
      final payloadWithNetworkKeyAllowed = {
        'modulePath': 'plugin.wasm',
        'commands': ['connect --network=true'],
        'wasiAllowedDirs': ['/tmp/valid'],
        'allowNetwork': true,
        'network': true,
      };
      expect(validatePayload(payloadWithNetworkKeyAllowed), isTrue);
    });
  });
}
