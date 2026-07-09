# Handoff — 3DGS Phoenix Unreal Engine Integration

**State:** 2026-07-09, end of session. Daemon binary pending compilation.

---

## What Exists

| Component | Path | State |
|---|---|---|
| MainMap | `app_unreal/Content/MainMap.umap` | Actors placed: CesiumGeoreference, Cesium3DTileset, CesiumSunSky |
| Cesium ion token | `app_unreal/Content/CesiumSettings/CesiumIonServers/CesiumIonSaaS.uasset` | Token saved (uasset grew from 1386→1981 bytes) |
| Map config | `app_unreal/Config/DefaultEngine.ini` | Points to `/Game/MainMap` (not `/Game/Maps/MainMap`) |
| UE project | `app_unreal/cesium_daemon.uproject` | UE 5.8, CesiumForUnreal enabled, BuildSettingsVersion V7 |
| Cesium plugin | `app_unreal/Plugins/CesiumForUnreal/` | Cloned from GitHub, EngineVersion 5.8, all submodules + GLM + async++ |
| Daemon C++ | `app_unreal/Source/cesium_daemon/` | cesium_daemon.h/.cpp, DaemonGameMode.h/.cpp, DaemonServer.h/.cpp, OffscreenRenderer.h/.cpp |
| Build.cs | `app_unreal/Source/cesium_daemon/cesium_daemon.Build.cs` | CesiumRuntime, RHI, RenderCore, Renderer, Sockets, Networking, Json, JsonUtilities + CoreVideo/IOSurface/Metal frameworks |
| Dart UDS client | `app_flutter/lib/domain/cesium_3d/grpc_channel.dart` | Real DaemonClient class, UDS sockets, JSON protocol, auto-reconnect |
| Daemon manager | `app_flutter/lib/domain/cesium_3d/unreal_daemon_manager.dart` | Spawns daemon, creates DaemonClient |
| Viewport | `app_flutter/lib/features/topology/scene_3d_viewport.dart` | Camera sync via UDS, IOSurface polling timer |
| Swift plugin | `app_flutter/macos/Runner/MainFlutterWindow.swift` | 90 lines. IOSurface import via updateFrame. No fake rendering. |
| Texture controller | `app_flutter/lib/domain/cesium_3d/native/mac_iosurface_texture_controller.dart` | init + updateFrame only |
| Flutter tests | `app_flutter/` | 209/209 pass, flutter analyze clean |
| GitHub issues | gintatkinson/3dgs-phoenix | Epic 3 (#248) and children (#251-#254, #257, #259-#262, #269) all reopened |
| Instructions | `app_unreal/MAINMAP_INSTRUCTIONS.md` | Step-by-step for UE editor (already executed) |
| Handoff doc | `HANDOFF.md` (repo root) | Previous detailed handoff |

## Deleted (cleanup done)

- `app_flutter/lib/domain/cesium_3d/native/mac_iosurface_bridge.dart` (fake hardcoded pointer)
- `app_flutter/test/.../mac_iosurface_interop_test.dart` (test for deleted bridge)
- Fake CoreGraphics rendering (~240 lines from MainFlutterWindow.swift)
- Fake GrpcChannel (rewritten as real DaemonClient)

## Immediate Next Action

Compile daemon binary:
```bash
/Users/Shared/Epic Games/UE_5.8/Engine/Build/BatchFiles/Mac/Build.sh cesium_daemon Mac Development "/Users/perkunas/jail/3dgs-phoenix/app_unreal/cesium_daemon.uproject"
```
Verify: `ls app_unreal/Binaries/Mac/cesium_daemon` → exists.

Then test headless:
```bash
cd /Users/perkunas/jail/3dgs-phoenix
./app_unreal/Binaries/Mac/cesium_daemon -RenderOffscreen -SceneId=test -log &
sleep 8
echo '{"type":"health_check"}' | nc -w2 -U /tmp/cesium_daemon_test.sock
# Expected: {"type":"health","status":"ok"}
kill %1
```

## Remaining Work (in order)

1. Confirm daemon binary compiles + UDS health check passes
2. Launch Flutter app → verify DaemonClient connects → camera sync → IOSurface flows to Texture widget
3. Implement crash recovery (Phase 4): detect exit code, freeze last frame, auto-restart, hot-swap texture, Lite Mode fallback
4. Package: `./scripts/package_app.sh` → test DMG end-to-end

## Lessons — Do NOT

- Write Unreal C++ without the editor open to verify APIs (DaemonServer broke from guessing)
- Make partial file edits — read the full file, understand the block boundaries, make one clean edit
- Give bullet lists when the user asks for plans — micro-tasks with tests and verification
- Commit or push without explicit permission
- Pretend to know the editor UI — search online or ask if stuck
- Disappear when agents run — the platform cancels them on any new message, so short fast actions are better than long silent agents
- Ignore explicit build output warnings (V7 was literally in the output, chose V6 instead)

## Notes for Editor Use

- The editor UI on macOS is unpolished. Use Outliner for actor selection, not viewport clicking.
- Token is in `Content/CesiumSettings/CesiumIonServers/CesiumIonSaaS.uasset` — double-click in Content Browser to edit
- `⌘⇧L` opens Output Log directly (menu path is unreliable across versions)
- Cmd+S saves — verify by checking file timestamps
