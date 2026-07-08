# Implementation Plan - Test Callback and Scenario 7 Rewrite

## 1. Objectives
- Add a visible-for-testing callback `onDrawVerticesForTesting` to `GlobeTileRenderer` in `app_flutter/lib/domain/cesium_3d/globe_tile_renderer.dart`.
- Trigger `onDrawVerticesForTesting` in `renderTiles` right before constructing `ui.Vertices`.
- Rewrite Scenario 7 test in `app_flutter/test/cesium_3d/globe_tile_renderer_test.dart` to use the new callback instead of manual grid-index building.
- Verify the callback works by asserting at least one execution.
- Run a TDD verification loop: comment out the `zs[i] < -1.5` check, verify the test fails, restore the check, verify the test passes.
- Stage, commit, and push changes to remote origin/main.

## 2. File Modifications

### `app_flutter/lib/domain/cesium_3d/globe_tile_renderer.dart` (Modify)
- Add `@visibleForTesting void Function(List<ui.Offset> positions, List<int> indices)? onDrawVerticesForTesting;`
- In `renderTiles`, check if `onDrawVerticesForTesting != null` and call it with `(positions, indices)` right before creating `ui.Vertices`.

### `app_flutter/test/cesium_3d/globe_tile_renderer_test.dart` (Modify)
- Rewrite `Scenario 7 - Mesh geometry distortion validation sweep` to:
  - Instantiate a `FakeCanvas`.
  - Register `renderer.onDrawVerticesForTesting = (positions, indices) { MeshGeometryValidator.validate(positions: positions, indices: indices); };`
  - Call production `renderer.renderTiles` method.
  - Assert that `onDrawVerticesForTesting` was invoked at least once.

### `app_flutter/test/cesium_3d/adversarial_fuzzer_test.dart` (Create)
- Create a new adversarial fuzzer test with 1000 random camera viewpoints (latitude, longitude, altitude, heading, pitch).
- Mock `TileFetcher` to return simple base64-decoded tile image data and warm up the cache by fetching zoom 2 tiles.
- Instantiate `Scene3DViewportPainter` and a `FakeCanvas`.
- For each generated viewport, call `renderer.renderTiles` and hooks `MeshGeometryValidator.validate` on vertex generation to ensure no mesh distortion occurs.
- Harvest and report any failures during the fuzzer sweep, requiring zero failures for the test to pass.

## 3. Success / Verification Criteria
- `flutter test test/cesium_3d/globe_tile_renderer_test.dart` fails when `zs[i] < -1.5` check is commented out.
- `flutter test test/cesium_3d/globe_tile_renderer_test.dart` passes when `zs[i] < -1.5` check is restored.
- `flutter test test/cesium_3d/adversarial_fuzzer_test.dart` executes and passes cleanly with 0 failures under the 1000 fuzzer iterations.
- All git changes pushed to `origin/main` (or tracking branch) and clean git status (`git diff` empty).
