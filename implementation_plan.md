# Implementation Plan - Bootstrapping Embedded Unreal Engine C++ Project

## 1. Objectives
Bootstrap the directory structure, configuration files, and C++ source code files for the embedded Unreal Engine project `app_unreal/` inside the monorepo workspace.
Configure the root `.gitignore` to exclude Unreal Engine build artifacts.

## 2. File Modifications

### Root `.gitignore`
- Update `/Users/perkunas/jail/3dgs-phoenix/.gitignore` to ignore the following Unreal Engine intermediate build outputs:
  ```text
  # Unreal Engine intermediate directories
  app_unreal/Binaries/
  app_unreal/Intermediate/
  app_unreal/Saved/
  app_unreal/DerivedDataCache/
  app_unreal/Build/
  app_unreal/*.xcworkspace
  app_unreal/*.sln
  ```

### New Files to Create under `app_unreal/`
1. **`app_unreal/cesium_daemon.uproject`**:
   - Primary Unreal project descriptor.
   - Configure modules (`cesium_daemon`) and plugins (`CesiumForUnreal`).
2. **`app_unreal/Config/DefaultEngine.ini`**:
   - Engine configuration settings defining Default Map.
3. **`app_unreal/Source/cesium_daemon.Target.cs`**:
   - Build target configuration for the Game.
4. **`app_unreal/Source/cesium_daemonEditor.Target.cs`**:
   - Build target configuration for the Editor.
5. **`app_unreal/Source/cesium_daemon/cesium_daemon.Build.cs`**:
   - Module dependency rules for `cesium_daemon`.
6. **`app_unreal/Source/cesium_daemon/cesium_daemon.h`**:
   - Core header file for the module.
7. **`app_unreal/Source/cesium_daemon/cesium_daemon.cpp`**:
   - Primary C++ implementation module definition.
8. **`app_unreal/README.md`**:
   - Developer setup and compilation guide on macOS.

## 3. Success / Verification Criteria
- Verify all required directories and files exist inside `app_unreal/`.
- Ensure files match the exact content specifications provided.
- `git diff` shows the expected updates.
