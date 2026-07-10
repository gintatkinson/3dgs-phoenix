# Handoff — Cesium-Native 3D Terrain Integration (July 11, 2026)

**State:** Clean foundation at `3e2265c`. Zero Unreal. Zero daemon. Zero progress on cesium-native.

## What Exists

| Component | Path | State |
|-----------|------|-------|
| Flutter app | `app_flutter/` | Builds, runs. CustomPaint globe renders with OSM tile fetch. Camera pan/zoom/rotate works. Entity/link overlay works. |
| Cesium bridge (stubs) | `cesium_native_bridge/src/bridge.cpp` | Real ECEF math. Tile functions stubbed (update_camera no-op, get_visible_tile_count returns 0, request_tile_data returns error). |
| Bridge CMake | `cesium_native_bridge/CMakeLists.txt` | Links Cesium3DTilesSelection, CesiumGeospatial, CesiumGeometry, CesiumUtility, CesiumAsync. Does NOT link CesiumCurl (HTTP) or CesiumIonClient (auth). |
| cesium-native | `cesium_native_bridge/third_party/cesium-native/` | Full source tree present. Not built outside bridge context. |
| Dart FFI bindings | `app_flutter/lib/domain/cesium_3d/native/bridge_bindings.dart` | 222 lines. Maps all existing C functions. |
| Dart engine wrapper | `app_flutter/lib/domain/cesium_3d/cesium_engine.dart` | 171 lines. Wraps bridge FFI calls. |
| Pipeline governance | `.pipeline/constitution.md`, `.pipeline/profiles/macos.md` | Written. Profiles reference old Unreal commands — need updating. |
| Blueprint doc | Old branch `feat/251-daemon-orchestration`: `docs/designs/cesium-native-flutter-3d-blueprint.md` | Authoritative architecture spec. |
| Implementation plan | Old branch: `docs/designs/cesium-native-implementation-plan.md` | 5-phase plan. Phases 1-3 partially attempted. |

## What Was Attempted and Failed

1. **Unreal Engine daemon** (10+ hours) — Compiling, cooking, IOSurface sharing, camera sync, crash recovery. All "worked" on paper but Cesium terrain never rendered. Root cause: MainMap had no Cesium actors. Final diagnosis: `RenderOffscreen` uses null viewport, SceneCapture captured magenta clear color. Abandoned for cesium-native approach.

2. **Cesium-native bridge Phase 1** (3 attempts) — Subagents produced correct-looking C++ code that compiled and linked. But network tests couldn't reach Cesium ion because the tileset URL was wrong (`assets.cesium.com` — dead domain) or DNS blocked. No integration test ever passed against real Cesium data. All "passes" were false positives from null checks and error handling, not real tile streaming.

3. **Cesium-native bridge Phase 2** (Dart FFI + CesiumEngine) — Methods written but never tested against real bridge output. No documentation.

4. **Cesium-native bridge Phase 3-4** (renderer split, Unreal cleanup) — Completed then reverted when session was abandoned.

## Current Branch: `feat/251-cesium-native-v2`

Clean at `3e2265c`. The production-quality commits (`415f9f0`, `7899120`, `7dadc1e` on old branch) are code that looks correct but was never verified against real Cesium data. The `415f9f0` commit added CesiumCurl (real HTTP) to the bridge — worth reviewing.

## Critical Unresolved Issues

1. **Cesium ion tileset URL is unknown.** `assets.cesium.com` is dead. `assets.ion.cesium.com` may also be wrong. The correct URL for Cesium World Terrain (asset ID 1) from ion needs to be determined from cesium-native documentation or test suite.

2. **Network/DNS blocks Cesium ion.** The macOS WiFi DNS (192.168.4.1) can't resolve the current URL. Test binary needs correct URL AND working DNS or network entitlements.

3. **Cesium ion token required.** The project had a token in `CesiumIonSaaS.uasset` (Unreal path, now deleted). A valid Cesium ion access token is needed for any real integration test. Token must come from environment or config file — never hardcoded.

4. **Canvas 2D ceiling.** CustomPaint cannot GPU texture-map terrain imagery. Flat-shaded triangles only. For high-fidelity terrain, a GPU renderer is needed (CesiumJS WebView discussed as future option).

5. **Documentation.** `.pipeline/profiles/macos.md` still references Unreal daemon build commands.

## What To Do Next (Recommended Order)

1. **Find correct Cesium ion tileset URL** — Check cesium-native's own test suite or documentation for the ion endpoint. Likely something like `https://ion.cesium.com/api/assets/1/endpoint` or similar construction.

2. **Add CesiumCurl + CesiumIonClient to CMake** — the bridge needs real HTTP and ion auth.

3. **Un-stub bridge functions** — `bridge_update_camera`, `bridge_get_visible_tile_count/id`, `bridge_request_tile_data`, `bridge_sample_terrain_height`, `bridge_ecef_to_screen`. See `bridge.h` for the C API — all declared, half implemented.

4. **Integration test against real Cesium data** — NOT null checks. Must verify: tile count > 0 after camera update, tile data is valid glTF > 1000 bytes, terrain height at SF is 0-100m.

5. **Document every public method** — Doxygen on bridge.h, Dart doc comments on cesium_engine.dart.

6. **Update `.pipeline/profiles/macos.md`** — remove Unreal sections, add bridge build commands.

7. **Coordinate the coordinator (you)** — Do not dispatch subagents without Cesium ion network access verified first. All previous subagent dispatches produced code that "passed" against stubs and dead URLs.

## Lessons (DO NOT)

- Trust subagent output that says "tests pass" — demand PASTED raw test output from real integration
- Use `assets.cesium.com` — it's dead
- Hardcode any URL in source code — it goes in test config or env vars
- Hardcode any Cesium ion token — env var `CESIUM_ION_TOKEN` only
- Accept "expected failure" or "SKIP" as a test pass
- Dispatch without verifying network access to Cesium ion first
- Build without verifying the built .dylib can actually load tiles
