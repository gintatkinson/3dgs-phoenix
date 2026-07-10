# Implementation Plan - macOS Profile Update and Bridge Implementation

## 1. Objectives
- Update `.pipeline/profiles/macos.md` to specify the exact target (`--target cesium_native_bridge`) when building the C++ bridge.
- Remove remaining Unreal Engine references in `.pipeline/profiles/macos.md` (specifically, `.uasset` reference).
- Update `cesium_native_bridge/src/bridge.cpp` to implement all tileset, camera, and tile retrieval functions using the `cesium-native` library.
- Add `CesiumGltf` and `CesiumGltfWriter` include directories and target link libraries to `cesium_native_bridge/CMakeLists.txt` to fix compiler missing headers/libraries.

## 2. File Modifications

### `.pipeline/profiles/macos.md`
- Change bridge compilation command:
  - From: `- **Bridge compilation:** `cd cesium_native_bridge && cmake --build build``
  - To: `- **Bridge compilation:** `cd cesium_native_bridge && cmake --build build --target cesium_native_bridge``
- Remove Unreal Engine references:
  - From: `- **API keys:** Cesium ion token stored in `.uasset` only — never in plaintext code files`
  - To: `- **API keys:** Cesium ion token resolved via the environment variable `CESIUM_ION_TOKEN` — never in plaintext code files`

### `cesium_native_bridge/src/bridge.cpp`
- Complete implementation of tileset, camera, and tile retrieval functions using `cesium-native`.

### `cesium_native_bridge/CMakeLists.txt`
- Add `${CESIUM_NATIVE_DIR}/CesiumGltf/include` and `${CESIUM_NATIVE_DIR}/CesiumGltfWriter/include` to target_include_directories.
- Add `CesiumGltf` and `CesiumGltfWriter` to target_link_libraries.

## 3. Success / Verification Criteria
- Verify the content of `.pipeline/profiles/macos.md`.
- Build the bridge target: `cmake --build . --target cesium_native_bridge`.
- Commit changes, push to the remote tracking branch, and verify that `git diff origin/feat/251-cesium-native-clean` is empty.
