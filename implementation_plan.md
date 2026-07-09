# Implementation Plan: Feature 47 (Windows DXGI Texture Interop)

This feature implements the Windows DXGI Texture Interop bridge classes and verification tests.

## Proposed Changes

### Component: Domain & Native Bridge

#### [NEW] [windows_dxgi_bridge.dart](file:///Users/perkunas/jail/3dgs-phoenix/app_flutter/lib/domain/cesium_3d/native/windows_dxgi_bridge.dart)
- Implement `InvalidDxgiHandle` implementing `Exception`.
- Implement `SurfaceBindingFailure` implementing `Exception`.
- Implement `FlutterWindowsEmbedder`:
  - Fields: `final String surfaceType`.
  - Constructor: `const FlutterWindowsEmbedder({required this.surfaceType})`.
  - Method: `bool bindSharedSurface(int handle)`:
    - If `handle == 0`, throws `InvalidDxgiHandle`.
    - Returns `true`.
- Implement `WindowsDxgiBridge`:
  - Fields: `final bool? _isWindowsOverride`.
  - Constructor: `const WindowsDxgiBridge({bool? isWindows}) : _isWindowsOverride = isWindows;`
  - Getter: `bool get _isWindows` to detect Windows platform (falling back to `Platform.isWindows` if override is null).
  - Method: `int createSharedHandle(int width, int height)`:
    - Validates `width > 0` and `height > 0`. Throws `SurfaceBindingFailure` if not.
    - Returns a mock handle value `2588` (simulating `0x0A1C`).
  - Method: `bool registerDxgiSurface(int handle)`:
    - If `handle == 0`, throws `InvalidDxgiHandle`.
    - Returns `true`.
  - Method: `bool validatePayload(Map<String, dynamic> payload)`:
    - Parses and validates payload schema.
    - Constraints validation:
      - `dxgiHandle` (string or parsed int) must not be zero/empty. Throws `InvalidDxgiHandle` if zero or empty.
      - Detect Windows platform: `Platform.isWindows` or the mock `isWindows` flag.
      - If running on Windows, validation must strictly enforce that `"surfaceType"` is `"kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle"`. If not, throws `InvalidDxgiHandle`.
      - Width and height must be positive, non-zero. If not, throws `SurfaceBindingFailure`.
      - If valid, returns `true`.

---

### Component: Verification & Test Suite

#### [NEW] [windows_dxgi_interop_test.dart](file:///Users/perkunas/jail/3dgs-phoenix/app_flutter/test/cesium_3d/windows_dxgi_interop_test.dart)
- Add unit tests verifying:
  - Given the application is running on Windows, the graphics bridge allocates/validates payload with shared handle and surface type `kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle` correctly.
  - Attempting to register an invalid or null handle (e.g. zero handle) throws `InvalidDxgiHandle`.
  - Dimension constraints validation on `createSharedHandle`.
  - Dimension constraints validation on `validatePayload`.
  - Non-Windows platform bypass validation checks for surfaceType.

---

## Verification Plan

### Automated Tests
- Run the newly created test suite:
  ```bash
  flutter test test/cesium_3d/windows_dxgi_interop_test.dart
  ```
