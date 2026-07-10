# Implementation Plan - Cesium 3D Engine Callbacks & Culling/LOD Utilities

## 1. Objectives
- Modify `CesiumEngine` in `app_flutter/lib/domain/cesium_3d/cesium_engine.dart` to support native error and tile callbacks via thread-safe `NativeCallable.listener`.
- Implement `LodSelector` in `app_flutter/lib/domain/cesium_3d/lod_selector.dart` to determine whether a tile should split using the Screen Space Error (SSE) formula.
- Implement `Culler` in `app_flutter/lib/domain/cesium_3d/culler.dart` to perform frustum and horizon culling in Earth-Centered, Earth-Fixed (ECEF) coordinates.
- Add unit tests for LOD selection and culling to verify mathematical correctness.

## 2. Target Files & Changes

### `app_flutter/lib/domain/cesium_3d/cesium_engine.dart`
- Set up static error handler callback:
  ```dart
  static void _onNativeError(int errorCode, Pointer<Utf8> message, Pointer<Void> userData) {
    final msg = message.toDartString();
    print('Native Error ($errorCode): $msg');
  }
  ```
- Store `_errorCallable` as a static field of `CesiumEngine` and pass `_errorCallable!.nativeFunction` to `_bindings.initialize`.
- Implement static `_pendingTileCallbacks` map.
- Implement static `_onTileReady` callback and shared `_tileReadyCallable = NativeCallable<BridgeTileReadyCallbackNative>.listener(_onTileReady)`.
- Update `requestTileData` to register callbacks in `_pendingTileCallbacks` and pass `_tileReadyCallable!.nativeFunction` to `_bindings.requestTileData`.
- Call `close()` on the native callables and clear callbacks in the `dispose()` method.

### `app_flutter/lib/domain/cesium_3d/lod_selector.dart`
- Create `LodSelector` class.
- Add method `shouldSplit(int zoom, int x, int y, double cameraAlt, double viewportWidth)`:
  - $\text{tileWidth} = 40075016.68 / (1 \ll \text{zoom})$
  - $SSE = (\text{tileWidth} / \text{cameraAlt}) \times \text{viewportWidth}$
  - Return `true` if $SSE > \text{threshold}$ (default threshold to e.g. 16.0 or configurable).

### `app_flutter/lib/domain/cesium_3d/culler.dart`
- Create `Culler` class.
- Add method `isVisible(Vector3 center, double radius, Vector3 cameraPos, Vector3 cameraDir, double fovRad)`:
  - Frustum culling: Check look angle between `cameraDir` and vector to tile center (taking radius into account).
  - Horizon culling: Using Earth radius $R = 6378137.0$ (ECEF), check if the tile is completely behind the horizon from the camera position.

### `app_flutter/test/cesium_3d/lod_selector_test.dart`
- Unit tests for `LodSelector` verifying that `shouldSplit` returns correct split decisions for various zoom levels, camera altitudes, and viewports.

### `app_flutter/test/cesium_3d/culler_test.dart`
- Unit tests for `Culler.isVisible` verifying that frustum and horizon culling work as expected under different viewing angles and elevations.

## 3. Success / Verification Criteria
- Run `flutter test` to ensure all tests pass.
- Run `flutter analyze` to verify clean static analysis.
- Verify `git diff origin/feat/251-cesium-native-clean` shows only the target files modified/added.
