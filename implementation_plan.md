# Implementation Plan: Feature 50 (Wasm Extensibility Subsystem)

This feature implements the Wasm Extensibility Subsystem in Flutter.

## Proposed Changes

### Component: Domain & WASM Subsystem

#### [NEW] [wasm_extensibility.dart](file:///Users/perkunas/jail/3dgs-phoenix/app_flutter/lib/domain/cesium_3d/wasm/wasm_extensibility.dart)
- Implement `WasiSandboxViolation` implementing `Exception`.
- Implement `WitInterfaceMismatch` implementing `Exception`.
- Implement `WasmtimeEngine`:
  - `bool initializeEngine()`: returns true.
  - `bool loadWasmModule(String modulePath)`:
    - If `modulePath` is empty, returns false.
    - If `modulePath` does not end with ".wasm", throws `WitInterfaceMismatch`.
    - Returns true.
- Implement `WasiConfigurator`:
  - `bool configureWasi(List<String> allowedDirs, bool allowNetwork)`:
    - Checks all paths in `allowedDirs`. If any path does not start with "/tmp", throws `WasiSandboxViolation`.
    - Returns true.
- Implement `WitMarshaller`:
  - `List<int> marshalRecord(String data)`: returns UTF-8 encoded bytes of `data`.
  - `String unmarshalRecord(List<int> bytes)`: returns UTF-8 decoded string of `bytes`.
- Implement `AsynchronousBatcher`:
  - Field: `final List<String> batchQueue = []`.
  - `bool enqueueCommand(String cmd)`: adds `cmd` to `batchQueue`, returns true.
  - `void flushBatch()`: clears `batchQueue`.
- Implement top-level function `bool validatePayload(Map<String, dynamic> payload)`:
  - If payload lacks "modulePath" or "commands", throws `WitInterfaceMismatch`.
  - If any directory in `wasiAllowedDirs` (expected to be a list in `payload['wasiAllowedDirs']` or similar field) does not start with "/tmp", throws `WasiSandboxViolation`.
  - If `allowNetwork` is false (expected in `payload['allowNetwork']`) and the payload simulates a network operation (e.g. contains "network" key or similar command flag is active in `commands`), throws `WasiSandboxViolation`.
  - Otherwise, returns true.

---

### Component: Verification & Test Suite

#### [NEW] [wasm_extensibility_test.dart](file:///Users/perkunas/jail/3dgs-phoenix/app_flutter/test/cesium_3d/wasm_extensibility_test.dart)
- Unit tests verifying:
  - Wasmtime runtime initialization, and that loading a valid plugin instantiates it within a restricted WASI sandbox (directory starts with "/tmp", network disabled).
  - Validation that directory paths outside "/tmp" throw `WasiSandboxViolation`.
  - Scenario 2: enqueuing multiple commands in `AsynchronousBatcher` and clearing them on `flushBatch()`.
  - Scenario 3: Restricting network capability throws `WasiSandboxViolation` when `allowNetwork: false` and a network operation is simulated in payload.

---

## Verification Plan

### Automated Tests
- Run the newly created test suite:
  ```bash
  flutter test test/cesium_3d/wasm_extensibility_test.dart
  ```
