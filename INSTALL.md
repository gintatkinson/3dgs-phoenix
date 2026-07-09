# Installation & Launch Guide: 3DGS Phoenix

This guide explains how to install and run the 3DGS Phoenix application with integrated Unreal Engine rendering.

## Prerequisites
- **macOS** (Metal-supported Apple Silicon or Intel)
- **Unreal Engine 5.8** (Installed or Source Build if you need to re-compile)

## Installation
1. Open the [3DGS-Phoenix.dmg](file:///Users/perkunas/jail/3dgs-phoenix/app_flutter/build/macos/Build/Products/Release/3DGS-Phoenix.dmg) file.
2. Drag the `app_flutter.app` bundle into your `/Applications` directory.

## Launching
Launch the app from `/Applications` or using the command line:
```bash
open /Applications/app_flutter.app --args --enable-impeller
```

## Features & Interface Navigation
- **3D Viewport Controls**:
  - **Zoom**: Scroll or pinch on the trackpad.
  - **Orbit/Pan**: Left-click and drag.
  - **Tilt/Pitch**: Right-click and drag.
  - **Keys**: Arrow keys orbit/tilt the camera.
