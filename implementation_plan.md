# Safety-Critical Implementation & Recovery Plan: Backlog De-Consolidation & Bug Rectification

This specification defines the complete engineering plan to de-consolidate the backlog into 5 granular feature issues and resolve the rendering, culling, and testing defects identified in the active workspace.

---

## 1. Architectural System Layout & Data Flow

```
+-----------------------------------------------------------------------------+
|                                FLUTTER ENGINE                               |
|                                                                             |
|   +---------------------------------------------------------------------+   |
|   |                       Scene3DGlobeViewport (UI)                     |   |
|   +----------------------------------+----------------------------------+   |
|                                      | Repaint / Viewport Size              |
|   +----------------------------------v----------------------------------+   |
|   |                        GlobePainter (CustomPaint)                   |   |
|   |  - Projects ECEF -> Screen Space                                    |   |
|   |  - Positions nodes and draws vertical ground anchoring drop lines   |   |
|   |  - Draws vertices using Custom GLSL Shaders                         |   |
|   +----+-----------------------------+-----------------------------+----+   |
|        | Samples                     | Binds                       |        |
|   +----v-----------------------+     |     +-----------------------v----+   |
|   |      TileAtlas (GPU VRAM)   |     |     |    Culler (ECEF Math)   |   |
|   |  - 16x16 slot texture      |     |     |  - Horizon & frustum culling|   |
|   |  - LRU Image evictions     |     |     |  - Curvature link culling  |   |
|   +----------------------------+     |     +----------------------------+   |
|                                      |                                      |
|   +----------------------------------v----------------------------------+   |
|   |                         CesiumEngine (Dart API)                     |   |
|   |  - Handles camera throttling (>=100ms, >=10m)                       |   |
|   |  - Maps callbacks via thread-safe NativeCallable.listener           |   |
|   +----+-----------------------------------------------------------+----+   |
|        | Dart FFI Boundary                                         |        |
|   +----v-----------------------------------------------------------v----+   |
|   |                      cesium_native_bridge (C++)                     |   |
|   |  - Spatial tileset octree, CurlHttpHandler, Ion Auth, glTF Writer   |   |
|   +----------------------------------+----------------------------------+   |
|                                      | Emits GLB (binary glTF) bytes        |
|   +----------------------------------v----------------------------------+   |
|   |                      TileProcessor (Dart Isolate)                   |   |
|   |  - Decodes GLB headers & chunks                                     |   |
|   |  - Verifies offset boundaries & index intervals                     |   |
|   |  - Registers mesh geometry & uploads texture to TileAtlas           |   |
|   +---------------------------------------------------------------------+   |
+-----------------------------------------------------------------------------+
```

---

## 2. Zero-Mocking Testing & Failure Detection Mandate

To comply with high-integrity software standards, **mock objects, stubs, and in-memory test doubles are strictly forbidden**. All tests must run against real, compiled dependencies, real assets, and actual platform bindings.

### 2.1 Real Image and Shader Instantiation
*   Tests requiring `ui.Image` references must run under a Flutter engine context using `testWidgets` to initialize `TestWidgetsFlutterBinding.ensureInitialized()`.
*   Images must be decoded from actual raw PNG/JPEG asset bytes (e.g. loading a 1x1 pixel test image from disk: `final codec = await ui.instantiateImageCodec(pngBytes);`).
*   Shaders must be compiled and loaded directly from their registered asset paths.

### 2.2 Live FFI Integration Testing
*   Dart FFI tests must load the actual compiled native binary (`libcesium_native_bridge.dylib` on macOS, `.so` on Linux, `.dll` on Windows) dynamically from the build outputs directory.
*   Assertions must verify that FFI callouts execute actual C++ logic, map pointers correctly in memory, and trigger error handlers when invalid values are passed.

### 2.3 Failure-Path Testing Requirements
*   **Malformed Asset Testing:** Tests must feed the parser corrupted GLB buffers (e.g. incorrect magic headers, index arrays referencing non-existent vertices, or offset values extending outside file length) and assert that it throws a `FormatException`.
*   **FFI Error Propagation:** Tests must manually invoke native FFI error conditions to verify that `CesiumEngine` captures the error, updates its internal state machine, and triggers the UI error display rather than silently printing to the console.
*   **Network Timeout Testing:** Tests must simulate a blocked socket connection (by requesting a tile but stubbing the network callback response to hang) and assert that after 5 seconds the system throws a `TileTimeoutException` and falls back to rendering parent tile geometry.

---

## 3. Collected Defects & Mathematical Corrections

We will resolve the following defects identified in the active workspace rendering:

### 3.1 Node Elevation Calculation Correction (Bug A)
*   **Symptom:** Nodes (such as `FUJI_SUMMIT-OPT-Core`) float high in outer space, detached from the elevated terrain peak.
*   **Root Cause:** Indiscriminate amplification of node local height ($H_{node} \times 2000.0$) in combination with terrain displacement ($H_{terrain} \times 80.0$) causes a massive altitude gap.
*   **Correction:** We will update `GlobePainter` to anchor the node position directly on the displaced surface:
    $$P_{node} = P_{unit} \times \left(R_{earth} + H_{terrain} \times 80.0\right) + N(P) \times H_{node}$$
    where the local building height $H_{node}$ is added linearly without the $2000.0x$ multiplier to keep the node seated directly on the elevated peak.

### 3.2 Vertical Drop Line Anchoring (Bug B)
*   **Symptom:** Floating nodes have no vertical drop line showing their anchor point on the ground.
*   **Correction:** We will implement drop line rendering in `GlobePainter` that draws a line from the node's displaced position $P_{node}$ down to the terrain's surface level:
    $$P_{anchor} = P_{unit} \times \left(R_{earth} + H_{terrain} \times 80.0\right)$$

### 3.3 Curvature Link Occlusion Culling (Bug C)
*   **Symptom:** Orange network link lines pass straight through the Earth's core or under the horizon.
*   **Correction:** Update the `Culler` to verify line-of-sight occlusion:
    *   Compute the minimum distance $d_{min}$ from the Earth's center to the straight line segment connecting node A and node B.
    *   If $d_{min} < R_{earth} + \text{local elevation}$, the line is blocked. We will cull the line or render it as a dashed fallback segment.

### 3.4 Label Collision Avoidance (Bug D)
*   **Symptom:** Screen-space text labels overlap and become unreadable.
*   **Correction:** Implement a simple 2D collision-avoidance check that shifts overlapping label bounding boxes vertically by their height offset when drawing them in screen space.

---

## 4. Proposed Changes

### Phase A: De-Consolidate Feature Specifications
We will generate 5 distinct, highly detailed feature specification files in `docs/features/`. Each specification will define the UML structure, API constraints, and Given-When-Then acceptance criteria for its specific subsystem.

#### 1. [NEW] [feat-19-gpu-texture-atlas.md](file:///Users/perkunas/jail/3dgs-phoenix/docs/features/feat-19-gpu-texture-atlas.md) (Issue #255)
*   **Target Subsystem:** GPU Texture Atlas Cache Manager.
*   **UML Classes:** `TileAtlas`, `AtlasResult`.
*   **Requirements:** LRU cache slot allocations, mock image handling, and VRAM memory-leak capacity sweeps.

#### 2. [NEW] [feat-20-geodetic-icosphere-generator.md](file:///Users/perkunas/jail/3dgs-phoenix/docs/features/feat-20-geodetic-icosphere-generator.md) (Issue #256)
*   **Target Subsystem:** Subdivided Geodetic Mesh Generator.
*   **UML Classes:** `GlobeMesh`.
*   **Requirements:** Tessellated icosahedron generation, UV wrapping, antimeridian polar pinch correction, and Uint16 index bounds checking.

#### 3. [NEW] [feat-21-binary-gltf-parser.md](file:///Users/perkunas/jail/3dgs-phoenix/docs/features/feat-21-binary-gltf-parser.md) (Issue #257)
*   **Target Subsystem:** Safety-Critical Binary glTF (GLB) Parser.
*   **UML Classes:** `GltfParser`, `GltfMesh`, `TileProcessor`, `TileGeometryCache`, `TileGeometry`.
*   **Requirements:** Magic bytes validation, chunk-length offset checks, unaligned buffer copies, and isolate-based asynchronous parsing.

#### 4. [NEW] [feat-22-sse-lod-culling-engine.md](file:///Users/perkunas/jail/3dgs-phoenix/docs/features/feat-22-sse-lod-culling-engine.md) (Issue #258)
*   **Target Subsystem:** SSE LOD & Frustum/Horizon Culling Engine.
*   **UML Classes:** `LodSelector`, `Culler`.
*   **Requirements:** Screen Space Error splitting thresholds, geodetic look-angle check, and Earth curvature horizon blockage culling.

#### 5. [NEW] [feat-23-thread-safe-ffi-bridge.md](file:///Users/perkunas/jail/3dgs-phoenix/docs/features/feat-23-thread-safe-ffi-bridge.md) (Issue #259)
*   **Target Subsystem:** Thread-Safe Native FFI Bridge and Camera Throttler.
*   **UML Classes:** `CesiumEngine`.
*   **Requirements:** `NativeCallable.listener` thread safety, camera update time/distance throttling, and callable resource disposals.

---

### Phase B: Rebuild Walkthroughs & Code Realization Tables
We will delete the consolidated `docs/designs/feat-251-solution.md` file and replace it with **5 individual solution walkthrough documents** corresponding to the new features. Each walkthrough will include:
*   An isolated **Code Realization Table** mapping only the files and symbols (classes, functions) for that specific feature.
*   An isolated **Verification Section** showing the raw output of only the test suite associated with that feature.

#### 1. [DELETE] [feat-251-solution.md](file:///Users/perkunas/jail/3dgs-phoenix/docs/designs/feat-251-solution.md)
#### 2. [NEW] [feat-255-solution.md](file:///Users/perkunas/jail/3dgs-phoenix/docs/designs/feat-255-solution.md) (GPU Texture Atlas Walkthrough)
#### 3. [NEW] [feat-256-solution.md](file:///Users/perkunas/jail/3dgs-phoenix/docs/designs/feat-256-solution.md) (Geodetic Mesh Generator Walkthrough)
#### 4. [NEW] [feat-257-solution.md](file:///Users/perkunas/jail/3dgs-phoenix/docs/designs/feat-257-solution.md) (Binary GLB Parser Walkthrough)
#### 5. [NEW] [feat-258-solution.md](file:///Users/perkunas/jail/3dgs-phoenix/docs/designs/feat-258-solution.md) (LOD & Culling Engine Walkthrough)
#### 6. [NEW] [feat-259-solution.md](file:///Users/perkunas/jail/3dgs-phoenix/docs/designs/feat-259-solution.md) (FFI Bridge & Throttler Walkthrough)

---

### Phase C: Governance & Epic Reconciliation
We will update the parent epic specifications to map these new features and verify complete traceability.

#### 1. [MODIFY] [epic-01-3d-visualization.md](file:///Users/perkunas/jail/3dgs-phoenix/docs/epics/epic-01-3d-visualization.md)
*   Add Features #256 and #258 to the checklist.

#### 2. [MODIFY] [epic-03-gpu-bridge.md](file:///Users/perkunas/jail/3dgs-phoenix/docs/epics/epic-03-gpu-bridge.md)
*   Update the checklist to replace the Unreal Daemon orchestration stubs with Features #255, #257, and #259.

#### 3. [MODIFY] [task.md](file:///Users/perkunas/.gemini/antigravity/brain/ba15de1d-f864-45bd-9c44-ec84cd20d871/task.md)
*   Replace the phased tasks with the de-consolidation deliverables checklist.

### Phase D: Zero-Mocking & Failure-Path Test Updates
We will modify the codebase and tests to enforce strict Zero-Mocking and Failure-Path Mandates.

#### 1. [MODIFY] [cesium_engine.dart](file:///Users/perkunas/jail/3dgs-phoenix/app_flutter/lib/domain/cesium_3d/cesium_engine.dart)
* Expose `@visibleForTesting` getters for throttling verification: `lastUpdateTime`, `lastLatitude`, `lastLongitude`, `lastAltitude`.
* Add a broadcast `errorStream` (using `StreamController<CesiumError>`) and static getters `lastNativeError`/`lastNativeErrorCode`.
* Update `_onNativeError` to record error code/message and emit to the `errorStream`. Reset errors on initialization/disposal.

#### 2. [MODIFY] [error_handler.dart](file:///Users/perkunas/jail/3dgs-phoenix/app_flutter/lib/domain/cesium_3d/native/error_handler.dart)
* Add `TileTimeoutException` and `CesiumError` definitions.

#### 3. [MODIFY] [tile_fetcher.dart](file:///Users/perkunas/jail/3dgs-phoenix/app_flutter/lib/domain/cesium_3d/tile_fetcher.dart)
* Accept optional `connectionTimeout` parameter in `TileFetcher` constructor.
* Add static `globalBaseUrlOverride` and instance `baseUrlOverride` fields.
* Catch `SocketException`/`TimeoutException` in `fetchTile` and throw `TileTimeoutException`.

#### 4. [MODIFY] [globe_tile_renderer.dart](file:///Users/perkunas/jail/3dgs-phoenix/app_flutter/lib/domain/cesium_3d/globe_tile_renderer.dart)
* Wrap asynchronous `fetchTile` calls in `_fetchAndDecode` in a try-catch to print and swallow `TileTimeoutException` or other exceptions, enabling parent-tile rendering fallback.

#### 5. [MODIFY] [gltf_parser_test.dart](file:///Users/perkunas/jail/3dgs-phoenix/app_flutter/test/cesium_3d/gltf_parser_test.dart)
* Add tests verifying that `parseGlb` throws `FormatException` when fed random corrupted/garbage byte buffers.

#### 6. [MODIFY] [tile_processor_test.dart](file:///Users/perkunas/jail/3dgs-phoenix/app_flutter/test/cesium_3d/tile_processor_test.dart)
* Convert to use `testWidgets` with `TestWidgetsFlutterBinding.ensureInitialized()`.
* Erase `MockTileAtlas` and use a real `TileAtlas` instead, verifying state updates directly via the cache.

#### 7. [MODIFY] [tile_atlas_lru_test.dart](file:///Users/perkunas/jail/3dgs-phoenix/app_flutter/test/cesium_3d/tile_atlas_lru_test.dart)
* Convert to use `testWidgets` with `TestWidgetsFlutterBinding.ensureInitialized()`.
* Erase `MockUiImage` entirely and decode real `ui.Image` objects from raw PNG bytes. Verify disposal by asserting that accessing `.width` on evicted images throws a `StateError`.

#### 8. [MODIFY] [tile_atlas_test.dart](file:///Users/perkunas/jail/3dgs-phoenix/app_flutter/test/cesium_3d/tile_atlas_test.dart)
* Convert to use `testWidgets` with `TestWidgetsFlutterBinding.ensureInitialized()`.
* Erase `MockImage` and use real decoded `ui.Image` objects.

#### 9. [MODIFY] [performance_leak_test.dart](file:///Users/perkunas/jail/3dgs-phoenix/app_flutter/test/cesium_3d/performance_leak_test.dart)
* Erase `FakeCesiumNativeBindings`.
* Use real `CesiumEngine` initialized with native library to verify camera update throttling using visible-for-testing getters.
* Assert that `CesiumEngine` captures native errors, updates state, and fires the broadcast error stream when native callbacks are invoked.

#### 10. [MODIFY] [tile_imagery_repaint_test.dart](file:///Users/perkunas/jail/3dgs-phoenix/app_flutter/test/cesium_3d/tile_imagery_repaint_test.dart)
* Erase all mock HTTP classes (`MockHttpOverrides`, `MockHttpClient`, etc.).
* Run a real local `HttpServer` to serve the tile PNG data. Configure `TileFetcher.globalBaseUrlOverride` to point to the local server.

---

## 5. Verification Plan

### Automated Verification
*   Run `flutter analyze` across all target directories to verify no warnings are introduced.
*   Run `flutter test` to ensure that all 96 unit tests remain 100% green.

### Independent Safety Audit
*   We will spawn a distinct `Safety Auditor` subagent to audit all 5 newly created feature files and 5 solution walkthrough files to verify compliance.
