# Blueprint: Cesium-Native 3D Terrain Mapping Without Unreal Engine

**Date:** 2026-07-09
**Version:** 1.0

---

## 1. Executive Summary

Removes the Unreal Engine daemon from the architecture entirely. All 3D rendering stays inside the Flutter process using the existing `cesium_native_bridge` C++ library for spatial math, tile selection, and terrain data — composited onto the Flutter canvas via Dart `CustomPaint`. No GPU interop. No IPC. No second process.

**What is deleted:** 460MB Unreal daemon binary, Swift IOSurface plugin complexity, DaemonClient/DaemonServer/gRPC, multi-process packaging.

**What stays:** Flutter app, topology UI, camera controller, the `cesium_native_bridge` C library (already compiled and linked).

**What is completed:** The unrealized 50% of `cesium_native_bridge` — un-stubbing tile operations, adding terrain elevation, wiring the render loop.

---

## 2. Architecture

```
┌──────────────────────────────────────────────────────┐
│                  Flutter macOS App                     │
│                                                        │
│  ┌──────────────────────────────────────────────┐     │
│  │            Layer 3: UI (Dart)                 │     │
│  │  Scene3DViewport, TopographyOverlay, CameraHUD│     │
│  └──────────────────┬───────────────────────────┘     │
│                     │                                  │
│  ┌──────────────────▼───────────────────────────┐     │
│  │         Layer 2: Domain / Render (Dart)       │     │
│  │  GlobeSceneController, GlobeTileRenderer,     │     │
│  │  CameraController, EntityManager, TileCache   │     │
│  └──────────────────┬───────────────────────────┘     │
│                     │ Dart FFI                         │
│  ┌──────────────────▼───────────────────────────┐     │
│  │           Layer 1: cesium_native_bridge (C++) │     │
│  │  TilesetLoader, CameraCuller, TerrainProvider,│     │
│  │  ECEF Transforms, Tile Data Fetcher           │     │
│  └──────────────────┬───────────────────────────┘     │
│                     │ HTTP                             │
│  ┌──────────────────▼───────────────────────────┐     │
│  │            Cesium ion / Tile Servers          │     │
│  │  3D Tiles, terrain heightmaps, imagery        │     │
│  └──────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────┘
```

### 2.1 Data Flow (Per Frame)

```
User drags camera
      │
      ▼
CameraController → camera state (lat, lon, alt, heading, pitch)
      │
      ▼ Dart FFI
CesiumEngine.updateCamera(CameraState)
      │ C++ cesium-native
      ├── Traverse 3D Tileset spatial index
      ├── Cull invisible tiles via frustum test
      ├── Select visible tile IDs with LoD metadata
      └── Queue missing tile downloads (async HTTP)
      │
      ▼ Dart FFI → returns visible tile list + camera view matrix
GlobeSceneController.update(dt)
      ├── For each visible tile:
      │     ├── Request tile glTF geometry (if not cached)
      │     └── Project tile vertices: ECEF → screen coordinates
      ├── For each entity: ECEF → screen projection
      ├── For each link: tessellate geodesic arc, project
      └── Build paint commands
      │
      ▼
Scene3DViewportPainter.paint(canvas, size)
      ├── Pass 1: Starfield background
      ├── Pass 2: Atmosphere gradient
      ├── Pass 3: Globe sphere + terrain elevation
      ├── Pass 4: Tile imagery (atlas sampling)
      ├── Pass 5: Entities (icons, labels)
      ├── Pass 6: Links (polylines, drop lines)
      └── Pass 7: HUD (reticle, camera stats)
```

---

## 3. cesium-native Bridge — Required API

### 3.1 Existing (Working)

| Function | Status |
|---|---|
| `bridge_cartographic_to_ecef(lat,lon,alt) → x,y,z` | ✅ Real |
| `bridge_ecef_to_cartographic(x,y,z) → lat,lon,alt` | ✅ Real |
| `bridge_initialize(TilesetConfig) → handle` | ✅ Real |
| `bridge_shutdown(handle)` | ✅ Real |
| `bridge_is_ready(handle)` | ✅ Real |
| `bridge_alloc/free` | ✅ Real |
| `bridge_last_error()` | ✅ Real |

### 3.2 Needs Un-stubbing

| Function | Current | Target |
|---|---|---|
| `bridge_update_camera(handle, CameraState)` | Returns OK (no-op) | Updates cesium-native view state, triggers tile tree traversal |
| `bridge_get_visible_tile_count(handle) → int` | Always returns 0 | Returns count of currently visible tiles after camera update |
| `bridge_get_visible_tile_id(handle, index) → tileId` | Always ERR_TILE | Returns tile ID string at given index |
| `bridge_request_tile_data(handle, tileId, callback) → status` | Always ERR_TILE | Fetches tile geometry (glTF) from cesium-native's cache or queues HTTP fetch, calls Dart callback when ready |
| `bridge_get_tile_bounding_volume(tileId) → {min, max}` | Not implemented | Returns ECEF bounding box for frustum/horizon culling on Dart side |

### 3.3 New Functions Needed

```c
// Terrain elevation at a geographic point
int32_t bridge_sample_terrain_height(int32_t handle, double lat, double lon, double* outHeight);

// Screen-space projection (replaces Dart's approximation)
int32_t bridge_ecef_to_screen(int32_t handle, double x, double y, double z, 
    CameraState* camera, int32_t viewW, int32_t viewH, 
    double* outScreenX, double* outScreenY);

// Set tile imagery provider (OpenStreetMap, ArcGIS Satellite, CartoDB Dark/Light)
int32_t bridge_set_imagery_provider(int32_t handle, const char* provider);

// Set terrain provider (cesium-world-terrain, ellipsoid-flat)
int32_t bridge_set_terrain_provider(int32_t handle, const char* provider);
```

---

## 4. Dart Bridge Layer

### 4.1 Updated `CesiumEngine` (already 171 lines)

**Add:**
```dart
class CesiumEngine {
  // NEW — real tile selection loop
  void updateCamera(VirtualCamera camera); // drives tile traversal
  
  // NEW — visible tile query
  List<String> getVisibleTileIds();
  
  // NEW — tile geometry request (async callback)
  Future<Uint8List?> requestTileGeometry(String tileId);
  
  // NEW — terrain height sample
  double sampleTerrainHeight(double lat, double lon);
  
  // NEW — screen projection (uses cesium-native ECEF math)
  Offset? cartographicToScreen(double lat, double lon, double alt, Size viewport);
  
  // NEW — imagery/terrain switching
  void setImageryProvider(ImageryProvider provider);
  void setTerrainProvider(TerrainProvider provider);
}
```

### 4.2 Updated `GlobeSceneController`

Currently does not exist as a centralized orchestrator. Must be created:

```dart
class GlobeSceneController {
  final CesiumEngine engine;
  final CameraController camera;
  final TileCache tileCache;       // Multi-tier: GPU textures + RAM + disk
  final EntityManager entities;
  final LinkManager links;
  
  RenderCommands commands;         // Built per frame, consumed by painter
  
  void update(double dt) {
    // 1. Update cesium-native camera
    engine.updateCamera(camera.current);
    
    // 2. Get visible tiles
    final tileIds = engine.getVisibleTileIds();
    tileCache.prune(tileIds);
    tileCache.requestMissing(tileIds);
    
    // 3. Project entities to screen
    for (final entity in entities.active) {
      entity.screenPos = engine.cartographicToScreen(
        entity.lat, entity.lng, entity.alt, viewportSize);
      entity.screenDepth = ...; // for z-sorting
    }
    
    // 4. Tessellate links
    for (final link in links.active) {
      link.segments = _tessellateArc(link.source, link.target);
    }
    
    // 5. Build render commands (culled, sorted)
    commands = _buildCommands();
  }
}
```

### 4.3 Updated `Scene3DViewportPainter`

Current `paint()` is 2100 lines doing everything in one class. Needs splitting:

```dart
class Scene3DViewportPainter extends CustomPainter {
  final RenderCommands commands;
  
  void paint(Canvas canvas, Size size) {
    // Delegate to specialized renderers
    _starfieldRenderer.paint(canvas, commands.starfield);
    _atmosphereRenderer.paint(canvas, commands.atmosphere);
    _globeRenderer.paint(canvas, commands.globe);      // sphere + terrain + tiles
    _entityRenderer.paint(canvas, commands.entities);
    _linkRenderer.paint(canvas, commands.links);
    _labelRenderer.paint(canvas, commands.labels);
    _hudRenderer.paint(canvas, commands.hud);
  }
}
```

---

## 5. What Gets Deleted

| Item | Reason |
|---|---|
| `app_unreal/` (entire directory — 2GB+) | Unreal Engine project, daemon binary, content |
| `app_unreal/Plugins/CesiumForUnreal/` | UE-specific Cesium wrapper — cesium-native is used directly via bridge |
| `app_flutter/macos/Runner/MainFlutterWindow.swift` most of it | IOSurface plugin — no external process, no GPU sharing |
| `app_flutter/lib/domain/cesium_3d/native/mac_iosurface_texture_controller.dart` | Method channel to Swift — not needed |
| `app_flutter/lib/domain/cesium_3d/native/` (windows_dxgi, linux_vulkan) | Platform-specific GPU bridges — not needed |
| `app_flutter/lib/domain/cesium_3d/grpc_channel.dart` (DaemonClient) | No IPC needed |
| `app_flutter/lib/domain/cesium_3d/unreal_daemon_manager.dart` | No external process to spawn |
| `app_flutter/lib/domain/cesium_3d/process_executor.dart` | No process spawning |
| `scripts/package_app.sh` (rewrite, not delete) | Remove daemon bundling — just `flutter build macos` |

**Estimated deletion:** ~15,000 lines of C++/Swift/Dart, 2GB disk.

---

## 6. What Gets Rewritten (Existing Dart Code)

| File | Change |
|---|---|
| `scene_3d_viewport.dart` | Remove daemon/texture code path. Remove `drawGlobe` toggle — always draw. Split `Scene3DViewportPainter` into render subclasses. |
| `globe_tile_renderer.dart` | Replace XYZ tile projection with cesium-native 3D Tiles geometry rendering |
| `tile_fetcher.dart` | Wire tile requests through cesium-native instead of direct HTTP |
| `camera_controller.dart` | Add ECEF camera export for cesium-native (already has lat/lon/alt, needs quaternion/matrix) |
| `cesium_engine.dart` | Complete the wrapper — add all un-stubbed methods (Section 3) |

---

## 7. Implementation Phases

### Phase 1: Un-stub tile operations (C++ bridge)

**Work orders:**
1. Implement `bridge_update_camera()` — connects to cesium-native `ITileset::updateView()`
2. Implement `bridge_get_visible_tile_count/Id()` — queries spatial index after view update
3. Implement `bridge_request_tile_data()` — returns glTF bytes from cesium-native tile cache or queues HTTP fetch
4. Add `bridge_sample_terrain_height()` — queries terrain provider
5. Add `bridge_ecef_to_screen()` — cesium-native projection math
6. Add `bridge_set_imagery_provider()` / `bridge_set_terrain_provider()` — runtime switching

**Verification per order:** C++ unit test passes, Dart FFI integration test passes.

### Phase 2: Dart engine wrapper + GlobeSceneController

**Work orders:**
1. Update `cesium_engine.dart` — add all new FFI method bindings
2. Create `globe_scene_controller.dart` — orchestrator per Section 4.2
3. Create `tile_cache.dart` — multi-tier cache (GPU/RAM/disk) with LRU eviction
4. Update `camera_controller.dart` — export full camera state matrix for cesium-native

**Verification per order:** Dart unit test verifies correct FFI calls, no crashes.

### Phase 3: Render pipeline

**Work orders:**
1. Split `Scene3DViewportPainter` into: GlobeRenderer, EntityRenderer, LinkRenderer, LabelRenderer, StarfieldRenderer, AtmosphereRenderer, HudRenderer
2. Update `GlobeRenderer` — draw terrain-displaced sphere using cesium-native height samples per vertex
3. Update `GlobeRenderer` — composite tile imagery atlas on globe surface
4. Update `EntityRenderer` — use `cesium_engine.cartographicToScreen()` for accurate projection
5. Update `LinkRenderer` — use cesium-native ECEF for geodesic arc tessellation
6. Implement frustum and horizon culling on Dart side using tile bounding volumes

**Verification per order:** Widget test verifies correct rendering. Performance benchmark: 60fps with 10k entities.

### Phase 4: Cleanup

**Work orders:**
1. Delete `app_unreal/` directory
2. Delete daemon manager, gRPC client, process executor from Dart
3. Strip Swift plugin, texture controller, platform bridges
4. Update `pubspec.yaml` — remove any gRPC/protobuf deps
5. Update `implementation_plan.md` — mark Unreal path as deprecated, describe new architecture
6. Update `package_app.sh` — `flutter build macos --release`
7. `flutter analyze` + `flutter test` — verify all passes

**Verification:** `flutter analyze` clean. All 209+ tests pass. No references to `unreal`, `daemon`, `iosurface` in codebase.

---

## 8. Frame Budget (16ms @ 60fps)

| Phase | Budget | Notes |
|---|---|---|
| Camera update + FFI | < 0.5ms | C function, no tile work on main thread |
| Tile cache management | < 1.0ms | Dart GC-friendly data structures |
| Entity/link projection | < 0.5ms | Batch ECEF transforms |
| Height sampling (per vertex) | < 2.0ms | Pre-computed for visible tile vertices |
| Canvas draw calls | < 8ms | GPU-accelerated by Impeller |
| Widget rebuild | < 2ms | HUD/config panel only |
| **Total** | **< 14ms** | 2ms headroom |

---

## 9. Memory Budget

| Component | Budget |
|---|---|
| cesium-native runtime | 100MB |
| Tile geometry cache (RAM) | 200MB |
| GPU texture atlas | 64MB |
| Entity/link data | 50MB |
| Dart heap | 100MB |
| **Total** | **~514MB** |

---

## 10. Key Design Decisions

| Decision | Rationale |
|---|---|
| Single-process | No IPC overhead. No GPU interop. Simpler debugging. |
| Canvas rendering (not Flutter GPU) | Canvas is proven, tested, and already working. `flutter_gpu` is experimental. |
| cesium-native for math only | It does no rendering — spatial math, tile selection, coordinate transforms. |
| No Unreal Engine | Removes 460MB binary, complex build system, editor dependency, offline GPU sharing. |
| Keep existing tile fetcher | Real OSM/ArcGIS HTTP fetcher already works — augment with cesium-native tile IDs. |
| Progressive enhancement | Start with current Canvas sphere + cesium-native tile IDs. Add terrain elevation later. Add 3D Tiles geometry later. Ship incrementally. |

---

## 11. Comparison: Unreal Path vs Cesium-Native Path

| Aspect | Unreal Engine Path | Cesium-Native Path |
|---|---|---|
| Binary size | 460MB daemon + 2GB Unreal assets | ~10MB Flutter app + ~50MB cesium-native .dylib |
| Build time | 2-10 minutes (CesiumRuntime compilation) | < 1 minute (Flutter hot reload) |
| GPU interop | Complex IOSurface/DXGI/Vulkan sharing | None needed |
| IPC | gRPC + UDS socket server | None |
| Rendering quality | AAA (PBR, atmospheric scattering, shadows) | Good (Canvas 2D, shader-free) |
| Editor required | Yes (Unreal Editor for map creation) | No |
| Crash resilience | Requires watchdog process + hot-swap | Standard Dart error handling |
| 3D Tiles | Cesium for Unreal Runtime | cesium-native direct |
| Terrain accuracy | Identical (same Cesium ion data) | Identical (same Cesium ion data) |
| Coordinate precision | Identical (WGS84 ECEF double) | Identical (WGS84 ECEF double) |
| iOS support | No (Unreal iOS build not planned) | Yes (CesiumRuntime + Impeller support iOS) |
| Android support | Complex | Yes |
| Web support | No | Future (WASM cesium-native) |

---

## 12. Verification Plan (End-to-End)

```bash
# 1. Build cesium_native_bridge
cd cesium_native_bridge && cmake --build build

# 2. Run C++ unit tests  
cd build && ctest

# 3. Run Dart FFI integration tests
cd app_flutter && flutter test test/cesium_3d/ffi_integration_test.dart

# 4. Run full test suite
flutter test

# 5. Launch app
flutter run -d macos

# 6. Manual verification:
# [ ] Globe renders with terrain elevation
# [ ] Satellite imagery tiles load and display
# [ ] Camera pan/zoom/rotate at 60fps
# [ ] Entities project correctly on globe surface
# [ ] Links render as geodesic arcs
# [ ] Labels billboard correctly
# [ ] Map style switching works (4 imagery types)
# [ ] Terrain toggle works
# [ ] No Unreal references in codebase
# [ ] No IOSurface references in codebase

# 7. Build release
flutter build macos --release
# Verify: app_flutter/build/macos/Build/Products/Release/app_flutter.app < 100MB
```
