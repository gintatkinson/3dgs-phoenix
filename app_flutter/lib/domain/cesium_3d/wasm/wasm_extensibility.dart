import 'dart:convert';

/// Exception thrown when a WASI sandbox violation is detected.
class WasiSandboxViolation implements Exception {
  final String message;

  const WasiSandboxViolation(this.message);

  @override
  String toString() => 'WasiSandboxViolation: $message';
}

/// Exception thrown when a WIT interface mismatch is detected.
class WitInterfaceMismatch implements Exception {
  final String message;

  const WitInterfaceMismatch(this.message);

  @override
  String toString() => 'WitInterfaceMismatch: $message';
}

/// Engine to initialize and manage Wasmtime runtime.
class WasmtimeEngine {
  /// Initializes the Wasmtime engine.
  bool initializeEngine() {
    return true;
  }

  /// Loads a WebAssembly module from the specified path.
  bool loadWasmModule(String modulePath) {
    if (modulePath.isEmpty) {
      return false;
    }
    if (!modulePath.endsWith('.wasm')) {
      throw const WitInterfaceMismatch('Module path must end with .wasm');
    }
    return true;
  }
}

/// Configurator for the WebAssembly System Interface (WASI) sandbox environment.
class WasiConfigurator {
  /// Configures WASI sandbox constraints.
  bool configureWasi(List<String> allowedDirs, bool allowNetwork) {
    for (final String path in allowedDirs) {
      if (!path.startsWith('/tmp')) {
        throw const WasiSandboxViolation('Sandbox violation: path is outside /tmp');
      }
    }
    return true;
  }
}

/// Marshaller for WebAssembly Interface Types (WIT).
class WitMarshaller {
  /// Marshals a string record into UTF-8 bytes.
  List<int> marshalRecord(String data) {
    return utf8.encode(data);
  }

  /// Unmarshals UTF-8 bytes back into a string record.
  String unmarshalRecord(List<int> bytes) {
    return utf8.decode(bytes);
  }
}

/// Batcher for executing multiple commands asynchronously.
class AsynchronousBatcher {
  final List<String> batchQueue = [];

  /// Enqueues a command to the batch queue.
  bool enqueueCommand(String cmd) {
    batchQueue.add(cmd);
    return true;
  }

  /// Flushes all enqueued commands, clearing the batch queue.
  void flushBatch() {
    batchQueue.clear();
  }
}

/// Validates payload attributes and constraints for the Wasm Extensibility Subsystem.
bool validatePayload(Map<String, dynamic> payload) {
  // WIT interface mismatch: if payload lacks "modulePath" or "commands", throws WitInterfaceMismatch.
  if (!payload.containsKey('modulePath') || !payload.containsKey('commands')) {
    throw const WitInterfaceMismatch('Payload lacks modulePath or commands');
  }

  // Directory namespace constraint: if any directory in wasiAllowedDirs does not start with "/tmp", throws WasiSandboxViolation.
  final dynamic allowedDirs = payload['wasiAllowedDirs'];
  if (allowedDirs is List) {
    for (final dynamic dir in allowedDirs) {
      if (dir is String) {
        if (!dir.startsWith('/tmp')) {
          throw WasiSandboxViolation('Sandbox violation: directory $dir does not start with /tmp');
        }
      }
    }
  }

  // Network capability constraint: if allowNetwork is false and the payload simulates a network operation, throws WasiSandboxViolation.
  final dynamic allowNetwork = payload['allowNetwork'];
  if (allowNetwork == false) {
    bool simulatesNetwork = false;
    
    // Check for "network" key in payload.
    if (payload.containsKey('network')) {
      simulatesNetwork = true;
    }
    
    // Check if any command simulates a network operation.
    final dynamic commands = payload['commands'];
    if (commands is List) {
      for (final dynamic cmd in commands) {
        if (cmd is String) {
          final String lowerCmd = cmd.toLowerCase();
          if (lowerCmd.contains('network') || lowerCmd.contains('--network') || lowerCmd.contains('-net')) {
            simulatesNetwork = true;
            break;
          }
        }
      }
    } else if (commands is String) {
      final String lowerCmd = commands.toLowerCase();
      if (lowerCmd.contains('network') || lowerCmd.contains('--network') || lowerCmd.contains('-net')) {
        simulatesNetwork = true;
      }
    }

    if (simulatesNetwork) {
      throw const WasiSandboxViolation('Sandbox violation: network access is disabled');
    }
  }

  return true;
}
