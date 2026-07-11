# Safety-Critical Implementation Plan: Cesium-Native 3D Terrain Integration (Phases 4, 5, & 6)

This specification defines the complete, zero-defect engineering design and TDD execution plan for the final three integration phases, complying with the strict mandates of the `feature-driven-implementation` skill.

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
|   |  - Applies terrain height vertex displacement                       |   |
|   |  - Draws vertices using Custom GLSL Shaders                         |   |
|   +----+-----------------------------+-----------------------------+----+   |
|        | Samples                     | Binds                       |        |
|   +----v-----------------------+     |     +-----------------------v----+   |
|   |      TileAtlas (GPU VRAM)   |     |     |    Culler (ECEF Math)   |   |
|   |  - 16x16 slot texture      |     |     |  - Horizon culling         |   |
|   |  - LRU Image evictions     |     |     |  - Frustum culling         |   |
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

## 2. Phase 4: Safety-Critical Tile Data Decoding & Processing

**Goal:** Parse binary glTF (GLB) assets returned by native FFI worker threads to extract 3D mesh geometry buffers (positions, indices, UV coordinates) and embedded imagery textures.

### 2.1 Interface & Data Structures

#### `GltfMesh` Class Signature
```dart
/// Represents parsed 3D mesh geometry and texture data from a binary glTF (GLB) container.
class GltfMesh {
  /// Flat array of vertex positions in model space: [x0, y0, z0, x1, y1, z1, ...]
  final Float32List positions;

  /// Flat array of texture mapping coordinates: [u0, v0, u1, v1, ...]
  final Float32List texCoords;

  /// Array of vertex indices defining the triangles: [i0, i1, i2, ...]
  final Uint16List indices;

  /// Extracted raw image bytes (PNG/JPEG) of the tile's texture, if present.
  final Uint8List? imageBytes;

  GltfMesh({
    required this.positions,
    required this.texCoords,
    required this.indices,
    this.imageBytes,
  });
}
```

### 2.2 Micro-Task TDD Execution Breakdown (Phase 4)

Each micro-task is executed as a context-isolated subagent dispatch following the TDD (RED-GREEN-REFACTOR) cycle.

#### Micro-Task 4.1: GLB Binary Header and Chunk Validation
*   **Target File:** `app_flutter/lib/domain/cesium_3d/gltf_parser.dart`
*   **Objective:** Read GLB byte buffer and validate the container header (magic bytes, version) and chunk offsets.
*   **RED Test (Failing Test):** Create `test/cesium_3d/gltf_parser_test.dart`. Write test `throwsFormatExceptionOnCorruptedHeader` which feeds the parser random bytes and asserts that a `FormatException` is thrown.
*   **GREEN Implementation:**
    *   Read first 4 bytes: verify equals `0x46546C67` ("glTF").
    *   Read next 4 bytes: verify equals version `2`.
    *   Read next 4 bytes: verify total length matches input byte length.
    *   Loop chunks: verify chunk length does not exceed remaining file length.
*   **Verification Gate:** Run `flutter test test/cesium_3d/gltf_parser_test.dart` and verify the test passes.

#### Micro-Task 4.2: Accessor Parse & Boundary Asserter
*   **Target File:** `app_flutter/lib/domain/cesium_3d/gltf_parser.dart`
*   **Objective:** Parse the GLB JSON chunk, locate buffer views, and map binary arrays (`POSITION`, `TEXCOORD_0`, and indices).
*   **RED Test (Failing Test):** In `gltf_parser_test.dart`, write test `extractsMeshGeometryBuffers` passing a valid mock GLB buffer and asserting that parsed positions, texture coordinates, and indices contain expected values. Write test `throwsFormatExceptionOnIndexOutOfBounds` where the indices chunk references a vertex index greater than or equal to `vertexCount`.
*   **GREEN Implementation:**
    *   Parse the JSON chunk to extract `accessors`, `bufferViews`, and `images`.
    *   Verify bufferView `byteOffset` + `byteLength` does not exceed the binary chunk's size.
    *   Convert float positions and texture coordinates into typed views (`Float32List`).
    *   Map indices to `Uint16List`. Verify index values are bounded in $[0, \text{vertexCount} - 1]$.
*   **Verification Gate:** Run `flutter test test/cesium_3d/gltf_parser_test.dart` to verify passing assertions.

#### Micro-Task 4.3: Tile Processor Integration
*   **Target File:** `app_flutter/lib/domain/cesium_3d/tile_processor.dart`
*   **Objective:** Coordinate incoming native FFI data events, run the parser in a Dart Isolate for payloads $>100\text{KB}$, and upload textures to the `TileAtlas`.
*   **RED Test (Failing Test):** Create `test/cesium_3d/tile_processor_test.dart`. Write test `processesFfiDataAndPopulatesAtlas` asserting that when tile bytes arrive, they are parsed and the resulting `ui.Image` is uploaded to `TileAtlas`.
*   **GREEN Implementation:**
    *   Implement `TileProcessor` Class.
    *   Wire FFI callbacks via `NativeCallable.listener` (`_onTileReady`).
    *   If payload $>100\text{KB}$, spawn isolate `Isolate.run(() => GltfParser().parseGlb(bytes))`.
    *   Decode PNG/JPEG bytes to `ui.Image` and upload it to `TileAtlas`.
*   **Verification Gate:** Run `flutter test test/cesium_3d/tile_processor_test.dart`.

---

## 3. Phase 5: Terrain Displacement & Imagery Texturing

**Goal:** Apply extracted heightmap data to displace vertices of the icosphere mesh in screen space, and sample the texture atlas using normalized UV coordinates.

### 3.1 Mathematical Models

#### 1. Geodetic Normal Vector Calculation
For a point $P_{unit} = (x, y, z)$ on the unit sphere:
$$N(P) = \frac{P_{unit}}{\|P_{unit}\|}$$

#### 2. Height Displacement Formula
Displace the vertex position along the normal using the elevation height value $H$ extracted from the terrain heightmap:
$$P_{displaced} = P_{unit} \times \left(R_{earth} + H \times S\right)$$
where:
*   $R_{earth} = 6,378,137.0$ meters (WGS84 Equatorial Radius).
*   $S = 1.0$ (Height scaling factor).
*   $H$ is validated to lie within the interval $[-12000.0, 9000.0]$. If $H \notin [-12000.0, 9000.0]$, it is clamped to $0.0$ to prevent coordinate explosions.

#### 3. GPU Texture Atlas UV Mapping
To prevent sampling bleed from adjacent slots in the `TileAtlas`, we transform the local UV coordinates $(u, v)$ to global atlas space $(U, V)$ using the slot scale and offset:
$$U = u \times uScale + uOffset$$
$$V = v \times vScale + vOffset$$
To eliminate edge seams, we clamp the global UV coordinates using a half-pixel margin:
$$U_{clamped} = \text{clamp}\left(U, uOffset + \epsilon, uOffset + uScale - \epsilon\right)$$
where $\epsilon = \frac{0.5}{\text{AtlasWidth}}$.

### 3.2 Micro-Task TDD Execution Breakdown (Phase 5)

#### Micro-Task 5.1: GlobePainter Height Displacement
*   **Target File:** `app_flutter/lib/domain/cesium_3d/renderers/globe_renderer.dart`
*   **Objective:** Modify `GlobePainter` to deform the sphere geometry outward along normal vectors based on height values.
*   **RED Test (Failing Test):** Create `test/cesium_3d/globe_deformation_test.dart`. Write test `displacesVerticesAlongGeodeticNormals` asserting that a vertex at unit vector $(1, 0, 0)$ with a height of $1000\text{m}$ projects to $(R_{earth} + 1000, 0, 0)$. Write test `clampsInvalidHeightToZero` to ensure `NaN`, `Infinity`, or out-of-bounds heights cause $0\text{m}$ displacement.
*   **GREEN Implementation:**
    *   In `GlobePainter.paint`, loop over mesh vertices.
    *   Compute normal vector. Verify finite bounds.
    *   Apply displacement: $P_{displaced} = P_{unit} \times (R_{earth} + \text{clamp}(H, -12000, 9000))$.
    *   Project displaced vectors to screen space.
*   **Verification Gate:** Run `flutter test test/cesium_3d/globe_deformation_test.dart`.

#### Micro-Task 5.2: Fragment Shader Sub-Texture Sampling
*   **Target File:** `app_flutter/shaders/globe.frag`
*   **Objective:** Modify shader to read atlas offsets/scales and sample sub-textures cleanly.
*   **RED Test (Failing Test):** Create `test/cesium_3d/globe_shader_test.dart`. Assert that painter binds the `TileAtlas` offset and scale uniforms correctly before invoking the draw call.
*   **GREEN Implementation:**
    *   Declare `uniform vec2 uOffset;` and `uniform vec2 uScale;` in `globe.frag`.
    *   Transform UV coordinates in the main loop: `vec2 atlasUv = localUv * uScale + uOffset;`.
    *   Clamp boundaries by subtracting a half-pixel width.
*   **Verification Gate:** Compile shaders via `flutter build macos --config-only` and run the shader test.

---

## 4. Phase 6: Threading, Performance & Cache Reconciliation

**Goal:** Throttle camera update lookups to prevent thread starvation, manage VRAM garbage collection, and enforce LRU cache memory stability during rapid viewport rotation.

### 4.1 Throttling State Machine

```
      [Camera Movement Event]
                 |
                 v
     Is elapsed time < 100ms?
         /              \
       Yes              No
       /                  \
   [Discard]        Is delta distance < 10 meters?
                        /               \
                      Yes               No
                      /                   \
                  [Discard]          [Execute FFI Update]
```

### 4.2 Micro-Task TDD Execution Breakdown (Phase 6)

#### Micro-Task 6.1: Camera Update Throttling
*   **Target File:** `app_flutter/lib/domain/cesium_3d/cesium_engine.dart`
*   **Objective:** Throttle FFI update frequency based on camera movement deltas and elapsed time.
*   **RED Test (Failing Test):** Create `test/cesium_3d/performance_leak_test.dart`. Write test `throttlesFrequentCameraUpdates` that sends 50 camera updates in a tight loop and asserts that the native FFI update was only invoked once.
*   **GREEN Implementation:**
    *   Add `_lastUpdateTime` (DateTime) and `_lastUpdatePosition` (Vector3) fields.
    *   Check thresholds in `updateCamera`: if `elapsed < 100ms` and `deltaDistance < 10m`, return immediately.
    *   Safely close `errorCallable` and `tileReadyCallable` in `dispose`.
*   **Verification Gate:** Run `flutter test test/cesium_3d/performance_leak_test.dart`.

#### Micro-Task 6.2: Atlas Slot Eviction Garbage Collection
*   **Target File:** `app_flutter/lib/domain/cesium_3d/renderers/tile_atlas.dart`
*   **Objective:** Call `.dispose()` immediately on evicted `ui.Image` references to prevent VRAM memory leaks.
*   **RED Test (Failing Test):** In `tile_atlas_test.dart`, write test `disposesEvictedImages` which fills the atlas capacity and asserts that the oldest evicted slot's image has its `.dispose()` method called.
*   **GREEN Implementation:**
    *   In `TileAtlas.allocateSlot` (upon LRU eviction), extract the evicted image handle.
    *   Call `evictedImage.dispose()` immediately.
    *   Implement an emergency clear that purges all slots if allocated textures exceed 512MB capacity.
*   **Verification Gate:** Run `flutter test test/cesium_3d/tile_atlas_test.dart`.

---

## 5. Source Code Documentation Standards

To prevent codebase maintenance drift and comply with safety-critical standards, inline comments and structured API documentation must be written concurrently during development.

### 5.1 C++ Doxygen Mandates (`bridge.h` / `bridge.cpp`)
All public interfaces must be documented using Doxygen blocks (`/** ... */`):
*   **`@brief`** — Clear, single-sentence summary of the function's purpose.
*   **`@param`** — Document each parameter, detailing its range constraints and nullability behaviors.
*   **`@return`** — Document return value status codes (e.g. `BRIDGE_OK`, `BRIDGE_ERR_CAMERA`).
*   **`@note`** — Thread-safety properties (e.g. "Called from native worker thread").

### 5.2 Dart Doc Mandates (`.dart`)
All Dart classes, constructors, methods, and properties must contain `///` docstrings:
*   Document parameters and assert conditions.
*   Document potential exception throws (such as `FormatException` or `StateError`).
*   Provide a code example for complex interactions.

---

## 6. Governance, Verification Independence, and Skill Mapping

To achieve strict verification safety, the project enforces structural separation between development and verification phases.

### 6.1 Process Roles & Actor Isolation
1.  **Isolated Development (Subagents):** Code modifications and unit tests are written exclusively by isolated subagents (`TypeName: self`).
2.  **Independent Safety Audit (Safety Auditor Subagent):**
    *   Before declaring a phase complete, the Coordinator spawns a **distinct, isolated auditor subagent** named `Safety Auditor`.
    *   This auditor runs with no access to the implementation subagents' logs.
    *   Its only role is to run static analysis tools (`flutter analyze`), verify that all test suites pass, check for Doxygen/Dart Doc compliance, and perform a strict compliance audit of the code changes using the `spec-implementation-auditor` skill.
3.  **Human-in-the-Loop Certification (The Human User):**
    *   All validation reports and codebase diffs are formatted into `walkthrough.md` and presented to you (the human system engineer) for final review and sign-off.

### 6.2 Skill Matrix Mapping

| Phase / Deliverable | Type | Writer / Owner | Pipeline Skill Applied |
| :--- | :--- | :--- | :--- |
| **`task.md` (Checklist)** | Artifact | Coordinator | `feature-driven-implementation` |
| **`walkthrough.md` (Walkthrough)** | Artifact | Coordinator | `feature-driven-implementation` |
| **`gltf_parser.dart` & `_test.dart`** | Code / Test | Development Subagent | `feature-driven-implementation` (TDD loop) |
| **`tile_processor.dart` & `_test.dart`** | Code / Test | Development Subagent | `feature-driven-implementation` (TDD loop) |
| **`globe_renderer.dart` (Displacement)** | Code / Test | Development Subagent | `feature-driven-implementation` (TDD loop) |
| **`globe.frag` (Shader Compositing)** | Shader | Development Subagent | `feature-driven-implementation` (TDD loop) |
| **`cesium_engine.dart` (Throttling)** | Code / Test | Development Subagent | `feature-driven-implementation` (TDD loop) |
| **`tile_atlas.dart` (Disposal / GC)** | Code / Test | Development Subagent | `feature-driven-implementation` (TDD loop) |
| **Compiler Errors / Runtime Fixes** | Bug Fix | Development Subagent | `debug-protocol` (8-step troubleshooting loop) |
| **Source Code Documentation Checks** | Doc Audit | **Safety Auditor Subagent** | `spec-implementation-auditor` (Documentation review) |
| **Codebase Verification Audit** | Audit | **Safety Auditor Subagent** | `spec-implementation-auditor` (Zero-loss check) |
| **Git Command Executions** | Commands | Coordinator | `accidental-data-loss-prevention` (Safety check) |
