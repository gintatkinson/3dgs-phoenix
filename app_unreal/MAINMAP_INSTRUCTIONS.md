# Phase 1.3: Create MainMap with Cesium Actors

## Prerequisites

1. **Cesium ion account** — free tier works
   - Sign up at [cesium.com/ion/signup](https://cesium.com/ion/signup)
   - Go to **Access Tokens** → copy the default token

2. **Project builds** — the daemon must compile first (`BUILD SUCCEEDED`)

---

## Step 1: Open the project in Unreal Editor

```bash
open /Users/perkunas/jail/3dgs-phoenix/app_unreal/cesium_daemon.uproject
```

- If asked to rebuild modules, click **Yes**
- If asked about BuildSettingsVersion upgrade, click **Yes**
- Wait for shader compilation to finish

---

## Step 2: Enable Cesium plugin

- Menu: **Edit → Plugins**
- Search: `Cesium`
- Check ✅ **Cesium for Unreal**
- Restart the editor when prompted

---

## Step 3: Create the MainMap

- **File → New Level → Empty Level**
- **File → Save Current Level As...**
- Navigate to: `app_unreal/Content/`
- Create folder: `Maps`
- Save as: `MainMap`

> DefaultEngine.ini already references `/Game/Maps/MainMap`

---

## Step 4: Add Cesium actors

From the **Place Actors** panel, drag into the viewport:

### a) Cesium Georeference
- Defines WGS84 globe origin at lat=0, lon=0
- Place at world origin — default location is fine

### b) Cesium3DTileset
- **Source**: `Cesium ion`
- **Ion Asset ID**: `1` (Cesium World Terrain + Bing Maps)
- **Ion Access Token**: paste your token from cesium.com/ion/tokens

### c) Cesium SunSky
- Adds atmospheric lighting
- Place anywhere in the level

### d) Player Start
- Place above globe surface for initial camera viewpoint
- Set location to `(0, 0, 5000000)` — 5000km above origin

---

## Step 5: Set GameMode

- **Edit → Project Settings → Maps & Modes**
- **Default GameMode**: select `DaemonGameMode`

---

## Step 6: Verify in-editor

- Click **Play** (or Alt+P)
- Should see a globe with real terrain/satellite imagery
- Check **Output Log** (Window → Developer Tools → Output Log) for:
  ```
  DaemonServer: Listening on /tmp/cesium_daemon_default.sock
  ```

---

## Step 7: Save

- **File → Save All**
- MainMap saved to: `app_unreal/Content/Maps/MainMap.umap`

---

## Result

After this, the daemon can be launched headless via:
```bash
./app_unreal/Binaries/Mac/cesium_daemon -RenderOffscreen -SceneId=default
```
It will:
- Load MainMap with Cesium globe
- Create OffscreenRenderer → IOSurface frame output
- Start UDS server on `/tmp/cesium_daemon_default.sock`
- Accept camera updates via JSON `{"type":"update_camera",...}`
- Return IOSurface ID via `{"type":"get_iosurface_id"}`
