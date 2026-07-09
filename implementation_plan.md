# Implementation Plan: Unreal Target Configuration and Project Compilation

This plan covers editing the Unreal Target configuration files to use an override build environment and compiling the C++ project.

## Proposed Changes

### Component: Unreal Target Configuration

#### [MODIFY] [cesium_daemon.Target.cs](file:///Users/perkunas/jail/3dgs-phoenix/app_unreal/Source/cesium_daemon.Target.cs)
- Remove `BuildEnvironment = TargetBuildEnvironment.Unique;` inside the constructor.
- Add `bOverrideBuildEnvironment = true;` inside the constructor.

#### [MODIFY] [cesium_daemonEditor.Target.cs](file:///Users/perkunas/jail/3dgs-phoenix/app_unreal/Source/cesium_daemonEditor.Target.cs)
- Remove `BuildEnvironment = TargetBuildEnvironment.Unique;` inside the constructor.
- Add `bOverrideBuildEnvironment = true;` inside the constructor.

#### [MODIFY] [cesium_daemon.uproject](file:///Users/perkunas/jail/3dgs-phoenix/app_unreal/cesium_daemon.uproject)
- Disable the `CesiumForUnreal` plugin by setting `"Enabled": false` to allow project compilation without the missing global plugin.

---

## Verification Plan

### Steps to run project files generator and compile
1. Run the project files generator script:
   ```bash
   /Users/Shared/Epic\ Games/UE_5.8/Engine/Build/BatchFiles/Mac/GenerateProjectFiles.sh -project="/Users/perkunas/jail/3dgs-phoenix/app_unreal/cesium_daemon.uproject" -game
   ```
2. Compile the project using the Mac Build script:
   ```bash
   /Users/Shared/Epic\ Games/UE_5.8/Engine/Build/BatchFiles/Mac/Build.sh cesium_daemon Mac Development "/Users/perkunas/jail/3dgs-phoenix/app_unreal/cesium_daemon.uproject"
   ```
3. Verify that compilation succeeds and that the binary exists under `app_unreal/Binaries/Mac/`.


## Unreal Daemon Integration

### Component: Flutter 3D Viewport

#### [MODIFY] [scene_3d_viewport.dart](file:///Users/perkunas/jail/3dgs-phoenix/app_flutter/lib/features/topology/scene_3d_viewport.dart)
- Add `import 'dart:io';` and `import 'package:app_flutter/domain/cesium_3d/unreal_daemon_manager.dart';` imports.
- Declare field `UnrealDaemonManager? _unrealDaemonManager;` in `Scene3DViewportState`.
- Implement `_initUnrealDaemon()` method inside `Scene3DViewportState`.
- Call `_initUnrealDaemon()` at the end of `initState()`.
- Add process cleanup in `dispose()`.

---

## Verification Plan for Unreal Daemon

1. Run static analysis via `flutter analyze` in `app_flutter/` to verify no errors exist.
