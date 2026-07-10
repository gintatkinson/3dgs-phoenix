#!/bin/bash
set -e

echo "=== 1. Building Flutter macOS App in Release Mode ==="
cd /Users/perkunas/jail/3dgs-phoenix/app_flutter
flutter build macos --release

echo "=== 2. Creating Resources Directories inside App Bundle ==="
APP_BUNDLE="/Users/perkunas/jail/3dgs-phoenix/app_flutter/build/macos/Build/Products/Release/app_flutter.app"
mkdir -p "$APP_BUNDLE/Contents/Resources/Binaries/Mac"
mkdir -p "$APP_BUNDLE/Contents/Resources/Saved/Cooked"

echo "=== 3. Building Staged Daemon (if needed) ==="
STAGED_DAEMON="/Users/perkunas/jail/3dgs-phoenix/app_unreal/Saved/StagedBuilds/Mac/cesium_daemon.app"
if [ ! -f "$STAGED_DAEMON/Contents/MacOS/cesium_daemon" ]; then
    echo "Building staged daemon..."
    /Users/Shared/Epic\ Games/UE_5.8/Engine/Build/BatchFiles/Mac/Build.sh cesium_daemon Mac Development "/Users/perkunas/jail/3dgs-phoenix/app_unreal/cesium_daemon.uproject"
    /Users/Shared/Epic\ Games/UE_5.8/Engine/Build/BatchFiles/RunUAT.sh BuildCookRun -project="/Users/perkunas/jail/3dgs-phoenix/app_unreal/cesium_daemon.uproject" -platform=Mac -cook -stage -pak -nop4 -SkipCookingEditorContent -unversionedcookedcontent -IgnoreCookErrors
fi

echo "=== 3b. Copying Staged Daemon Binary ==="
rm -f "$APP_BUNDLE/Contents/Resources/Binaries/Mac/cesium_daemon"
cp "$STAGED_DAEMON/Contents/MacOS/cesium_daemon" "$APP_BUNDLE/Contents/Resources/Binaries/Mac/cesium_daemon"

echo "=== 4. Copying Staged UE Content (Paks + Shaders) ==="
rm -rf "$APP_BUNDLE/Contents/Resources/UE"
cp -R "$STAGED_DAEMON/Contents/UE" "$APP_BUNDLE/Contents/Resources/UE"

echo "=== 4b. Copying Project Descriptor, Config and ICU Data ==="
cp "/Users/perkunas/jail/3dgs-phoenix/app_unreal/cesium_daemon.uproject" "$APP_BUNDLE/Contents/Resources/cesium_daemon.uproject"
mkdir -p "$APP_BUNDLE/Contents/Resources/Content"
rm -rf "$APP_BUNDLE/Contents/Resources/Content/Internationalization"
cp -R "/Users/Shared/Epic Games/UE_5.8/Engine/Content/Internationalization" "$APP_BUNDLE/Contents/Resources/Content/Internationalization"

rm -rf "$APP_BUNDLE/Contents/Resources/Config"
cp -R "/Users/perkunas/jail/3dgs-phoenix/app_unreal/Config" "$APP_BUNDLE/Contents/Resources/Config"

mkdir -p "$APP_BUNDLE/Contents/Engine"
rm -rf "$APP_BUNDLE/Contents/Engine/Config"
cp -R "/Users/Shared/Epic Games/UE_5.8/Engine/Config" "$APP_BUNDLE/Contents/Engine/Config"

echo "=== 5. Codesigning ==="
codesign --force -s - "$APP_BUNDLE/Contents/Resources/Binaries/Mac/cesium_daemon"
codesign --force -s - "$APP_BUNDLE"

echo "=== 6. Packaging into .dmg Installer ==="
hdiutil create -volname "3DGS-Phoenix" -srcfolder "$APP_BUNDLE" -ov -format UDZO "/Users/perkunas/jail/3dgs-phoenix/app_flutter/build/macos/Build/Products/Release/3DGS-Phoenix.dmg"
echo "=== Packaging Complete ==="
