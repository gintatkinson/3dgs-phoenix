# Implementation Plan - Scenario 4 Automated Tests

## 1. Objectives
Expose private testing wrappers in `GlobeTileRenderer` and add Scenario 4 BDD-style unit tests to verify visible tile grid and soft culling logic. Verify that they fail in a clean "RED" state on the current renderer codebase.

## 2. File Modifications
### `app_flutter/lib/domain/cesium_3d/globe_tile_renderer.dart`
- Add `import 'package:meta/meta.dart';`.
- Add `@visibleForTesting` wrapper `visibleTilesForTesting(VirtualCamera camera, ui.Size viewportSize)` delegating to `_visibleTiles(camera, viewportSize)`.
- Add `@visibleForTesting` wrapper `latLngToTileForTesting(double lat, double lng, int zoom)` delegating to `_latLngToTile(lat, lng, zoom)`.
- Add `@visibleForTesting` static method `calculateIndicesForTesting(List<double> zs)` running the single subdivision tile loop.

## 3. File Creations
### `app_flutter/test/cesium_3d/globe_tile_renderer_test.dart`
- Set up test suite for `GlobeTileRenderer`.
- **Test 1 (visible tile grid)**: Set up a `VirtualCamera` at altitude 500,000m. Invoke `visibleTilesForTesting`. Calculate expected horizon search offset (~16 tiles). Verify that tiles at the edge (dx >= 15) are returned. (Expected to fail).
- **Test 2 (soft culling)**: Set up 25 vertex depth values where some cross the horizon (visible z >= 0, hidden z < 0). Invoke `calculateIndicesForTesting`. Verify that triangles containing at least one visible vertex are not culled and their indices are populated. (Expected to fail).

## 4. Success / Verification Criteria
- Run `flutter test test/cesium_3d/globe_tile_renderer_test.dart` (or equivalent package-based test command).
- Verify that both tests fail in a clean "RED" state (Test 1 due to hardcoded 2-tile radius, Test 2 due to strict all-vertex z >= 0 culling).
- Ensure the project builds successfully with no compiler/static analysis errors in the test file.
