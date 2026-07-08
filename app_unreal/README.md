# Cesium Daemon - Unreal Engine Project

This is the embedded Unreal Engine C++ project directory structure and configurations inside the monorepo workspace.

## Prerequisites
- **macOS**
- **Xcode**
- **Unreal Engine 5.8**

## Developer Setup (macOS)

### 1. Generate Xcode Workspace
To generate the Xcode workspace project file (`.xcworkspace`), run the following command from the `app_unreal/` directory:

```bash
/Users/Shared/Epic\ Games/UE_5.8/Engine/Build/BatchFiles/Mac/GenerateProjectFiles.sh -project="$(pwd)/cesium_daemon.uproject" -game
```

### 2. Compile the Project
To compile the project, run the following build script:

```bash
/Users/Shared/Epic\ Games/UE_5.8/Engine/Build/BatchFiles/Mac/Build.sh cesium_daemon Mac Development "$(pwd)/cesium_daemon.uproject"
```
