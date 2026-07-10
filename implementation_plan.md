# Implementation Plan - macOS Profile Update

## 1. Objectives
- Update `.pipeline/profiles/macos.md` to specify the exact target (`--target cesium_native_bridge`) when building the C++ bridge.
- Remove remaining Unreal Engine references in `.pipeline/profiles/macos.md` (specifically, `.uasset` reference).

## 2. File Modifications

### `.pipeline/profiles/macos.md`
- Change bridge compilation command:
  - From: `- **Bridge compilation:** `cd cesium_native_bridge && cmake --build build``
  - To: `- **Bridge compilation:** `cd cesium_native_bridge && cmake --build build --target cesium_native_bridge``
- Remove Unreal Engine references:
  - From: `- **API keys:** Cesium ion token stored in `.uasset` only — never in plaintext code files`
  - To: `- **API keys:** Cesium ion token resolved via the environment variable `CESIUM_ION_TOKEN` — never in plaintext code files`

## 3. Success / Verification Criteria
- Verify the content of `.pipeline/profiles/macos.md`.
- Commit changes, push to the remote tracking branch, and verify that `git diff origin/feat/251-cesium-native-clean` is empty.
