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

