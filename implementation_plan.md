# Implementation Plan - Dual-Stage Culling/Clipping Fix & Regression Test

## 1. Objectives
- Add a new regression test `Test 5 (Scenario 6 - Discard triangles crossing behind camera)` to `app_flutter/test/cesium_3d/globe_tile_renderer_test.dart` to verify that triangles with any behind-camera vertex (depth <= -1.5) are correctly discarded/culled.
- Implement the camera plane depth-clamping update in `app_flutter/lib/features/topology/scene_3d_viewport.dart`.
- Implement triangle discarding logic for vertices crossing behind the camera plane in `app_flutter/lib/domain/cesium_3d/globe_tile_renderer.dart`.

## 2. File Modifications

### `app_flutter/test/cesium_3d/globe_tile_renderer_test.dart`
- Define `FakeCanvas` class mapping `ui.Canvas`:
  ```dart
  class FakeCanvas extends Fake implements ui.Canvas {
    int drawVerticesCount = 0;
    @override
    void drawVertices(ui.Vertices vertices, ui.BlendMode blendMode, ui.Paint paint) {
      drawVerticesCount++;
    }
  }
  ```
- Inside the main `GlobeTileRenderer Scenario 4 BDD Tests` group, add `Test 5 (Scenario 6 - Discard triangles crossing behind camera)` test case at the end of the group.

### `app_flutter/lib/features/topology/scene_3d_viewport.dart`
- Around line 1230, modify the depthVal computation:
  ```dart
  final double depthVal;
  if (depth <= 0.0) {
    depthVal = -100.0;
  } else if (isCulled) {
    depthVal = -1.0;
  } else {
    depthVal = depth;
  }
  ```

### `app_flutter/lib/domain/cesium_3d/globe_tile_renderer.dart`
- Around lines 363-374, modify indices calculation to discard any triangle crossing behind the camera plane (`depthVal < -1.5`):
  ```dart
  // Triangle 1: (i0, i1, i2)
  if (zs[i0] < -1.5 || zs[i1] < -1.5 || zs[i2] < -1.5) {
    // Discard
  } else if (zs[i0] >= 0.0 || zs[i1] >= 0.0 || zs[i2] >= 0.0) {
    indices.add(i0);
    indices.add(i1);
    indices.add(i2);
  }

  // Triangle 2: (i1, i3, i2)
  if (zs[i1] < -1.5 || zs[i3] < -1.5 || zs[i2] < -1.5) {
    // Discard
  } else if (zs[i1] >= 0.0 || zs[i3] >= 0.0 || zs[i2] >= 0.0) {
    indices.add(i1);
    indices.add(i3);
    indices.add(i2);
  }
  ```

## 3. Success / Verification Criteria
- First, verify that the new test fails without the fixes.
- Apply the fixes and verify that the tests pass:
  `flutter test test/cesium_3d/globe_tile_renderer_test.dart test/topology/scene_3d_viewport_test.dart`
- Ensure `git diff origin/main` (or the tracking remote branch) is clean after changes are successfully pushed.

