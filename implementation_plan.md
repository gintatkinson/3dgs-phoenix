# Implementation Plan - Near-Plane Depth Clamping & Regression Test

## 1. Objectives
- Add a regression test for near-plane coordinate explosion to `app_flutter/test/topology/scene_3d_viewport_test.dart`.
- Fix depth clamping math in `app_flutter/lib/features/topology/scene_3d_viewport.dart` by using the absolute value of depth (`depth.abs()`) before clamping to prevent coordinates behind the camera from exploding.

## 2. File Modifications

### `app_flutter/test/topology/scene_3d_viewport_test.dart`
- Inside the `Scene3DViewportPainter horizon culling regression tests` group (around line 170), add the following test case:
  ```dart
  test('Near-plane coordinates do not explode for vertices behind camera', () {
    final camera = VirtualCamera.clamped(
      latitude: 35.0,
      longitude: 135.0,
      altitude: 200000.0, // 200 km altitude
      heading: 0,
      pitch: -23, // tilted view
      roll: 0,
    );

    final painter = Scene3DViewportPainter(
      camera: camera,
      activeStyle: 'dark',
      astronomicalBody: 'Earth',
      elevationActive: true,
      showDevices: true,
      showLinks: true,
      showLabels: true,
      showDropLines: true,
      userRotationX: 0.0,
      userTilt: 0.0,
      zoomScale: 1.0,
    );

    const Size viewportSize = Size(800, 600);
    const Offset viewportCenter = Offset(400.0, 300.0);

    // Project a point that is behind the camera plane
    final proj = painter.project(
      0.5, // 30 degrees latitude
      2.3, // 131 degrees longitude
      6378137.0, // surface
      viewportCenter,
      0.0,
      0.0,
      viewportSize,
    );

    // Check that the projected coordinates are safe and do not explode to huge values (e.g. > 5k pixels)
    expect(proj.offset.dx.abs(), lessThan(5000.0));
    expect(proj.offset.dy.abs(), lessThan(5000.0));
  });
  ```

### `app_flutter/lib/features/topology/scene_3d_viewport.dart`
- In `project` method (around line 1223):
  - Replace:
    ```dart
    final double safeDepth = depth <= 10000.0 ? 10000.0 : depth;
    ```
    with:
    ```dart
    final double absDepth = depth.abs();
    final double safeDepth = absDepth <= 10000.0 ? 10000.0 : absDepth;
    ```

- In `_getHorizonPath` method (around line 1325/1326):
  - Replace:
    ```dart
    final double safeDepth = depth <= 10000.0 ? 10000.0 : depth;
    ```
    with:
    ```dart
    final double absDepth = depth.abs();
    final double safeDepth = absDepth <= 10000.0 ? 10000.0 : absDepth;
    ```

## 3. Success / Verification Criteria
- Run target tests in `app_flutter` to ensure the updated test passes:
  `flutter test test/topology/scene_3d_viewport_test.dart`
- Stage, commit, and push the changes to remote tracking branch `origin/main`.
- Verify `git diff origin/main` is empty.
