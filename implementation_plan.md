# Implementation Plan - GPU Texture Atlas Manager

## 1. Objectives
- Implement `TileAtlas` in `app_flutter/lib/domain/cesium_3d/renderers/tile_atlas.dart` to manage a grid of texture slots using an LRU cache.
- Implement unit tests in `app_flutter/test/cesium_3d/tile_atlas_test.dart` to verify slot allocation, UV calculations, and LRU eviction.

## 2. File Modifications

### `app_flutter/lib/domain/cesium_3d/renderers/tile_atlas.dart`
- Create this file defining:
  - `TileAtlas` class with configurable `columns`, `rows`, `slotWidth`, `slotHeight`.
  - Grid slot allocation logic:
    - Return `Offset(col / cols, row / rows)` and `Size(1.0 / cols, 1.0 / rows)` for a tile ID.
    - If cached, update LRU status and return bounds.
    - If not cached, allocate a free slot or evict the least recently used tile.
  - Image storage:
    - Associate an image (supporting standard `ui.Image` or dynamic/mock images) with an allocated slot.
    - Dispose existing `ui.Image` instances when a slot is evicted or cleared.
  - State management methods:
    - `clear()` to release all images and reset mapping state.
    - Helper queries for sizes, slot indices, and cached tile count.

### `app_flutter/test/cesium_3d/tile_atlas_test.dart`
- Create a unit test file verifying:
  - Basic insertion of tile IDs and correct slot assignment.
  - Verification of UV offset and scale calculations (e.g., coordinates for slot (0,0), slot (0,1), etc.).
  - Correct LRU eviction behavior (filling a small grid, querying an older slot to make it MRU, inserting a new tile, and asserting that the expected slot/tile is evicted).
  - Storing and clearing mock images/objects in slots.

## 3. Success / Verification Criteria
- Run `flutter test test/cesium_3d/tile_atlas_test.dart` to ensure all tests pass.
- Run `flutter analyze` to verify clean static analysis without warnings/errors.
- Run `git diff origin/feat/251-cesium-native-clean` to verify the only changes are the two target files.
