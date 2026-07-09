# Implementation Plan: Feature 48 (macOS IOSurface Texture Interop)

This feature implements the macOS IOSurface Texture Interop bridge classes and verification tests.

## Proposed Changes

### Component: Domain & Native Bridge

#### [NEW] [mac_iosurface_bridge.dart](file:///Users/perkunas/jail/3dgs-phoenix/app_flutter/lib/domain/cesium_3d/native/mac_iosurface_bridge.dart)
- Implement `CvPixelBufferInfo`:
  - Fields: `final int storageMode`, `final bool isIoSurfaceBacked`.
  - Constructor: `const CvPixelBufferInfo({required this.storageMode, required this.isIoSurfaceBacked})`.
  - Method: `void configure() {}`.
- Implement `IoSurfaceCreationFailed` implementing `Exception`.
- Implement `MetalValidationError` implementing `Exception`.
- Implement `MacIosurfaceBridge`:
  - `int createIoSurface(int width, int height)`:
    - Validates `width > 0` and `height > 0`. Throws `IoSurfaceCreationFailed` if not.
    - Returns a dummy/mock pointer value `140735492982848`.
  - `bool bindMetalTexture(int surfaceRef)`:
    - If `surfaceRef == 0`, throws `ArgumentError` or `IoSurfaceCreationFailed`.
    - Returns true.
  - `bool validatePayload(Map<String, dynamic> payload)`:
    - Parses and validates payload schema.
    - Constraints validation:
      - `ioSurfaceRef` must not be zero. Throws `ArgumentError` or `IoSurfaceCreationFailed` if zero.
      - Detect Apple Silicon platform: `Platform.isMacOS` and checking if `Platform.version` (or CPU info) contains `arm64` or `aarch64`.
      - If running on Apple Silicon macOS hardware, validation must strictly enforce that `"mtlStorageMode"` is `"MTLStorageModeShared"`. If it is any other value (like `"MTLStorageModePrivate"`), throws `MetalValidationError`.
      - If valid, returns true.

---

### Component: Verification & Test Suite

#### [NEW] [mac_iosurface_interop_test.dart](file:///Users/perkunas/jail/3dgs-phoenix/app_flutter/test/cesium_3d/mac_iosurface_interop_test.dart)
- Add unit tests verifying:
  - Given the application is running on macOS Apple Silicon, the graphics bridge allocates/validates payload with shared storage mode correctly.
  - Creating/validating texture with unsupported storage mode (e.g., `"MTLStorageModePrivate"`) on Apple Silicon throws a `MetalValidationError`.
  - Validating zero pointer value for `ioSurfaceRef` throws `IoSurfaceCreationFailed` or similar exception.

---

## Verification Plan

### Automated Tests
- Run the newly created test suite:
  ```bash
  flutter test test/cesium_3d/mac_iosurface_interop_test.dart
  ```
