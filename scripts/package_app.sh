#!/bin/bash
set -e
echo "=== 1. Building Flutter macOS App in Release Mode ==="
cd /Users/perkunas/jail/3dgs-phoenix/app_flutter
flutter build macos --release

echo "=== 2. Creating Resources Directory inside App Bundle ==="
APP_BUNDLE="/Users/perkunas/jail/3dgs-phoenix/app_flutter/build/macos/Build/Products/Release/app_flutter.app"
mkdir -p "$APP_BUNDLE/Contents/Resources"

echo "=== 3. Copying Unreal Daemon Binary ==="
cp "/Users/perkunas/jail/3dgs-phoenix/app_unreal/Binaries/Mac/cesium_daemon" "$APP_BUNDLE/Contents/Resources/cesium_daemon"

echo "=== 4. Copying Dependent Shared Libraries ==="
cp "/Users/perkunas/jail/3dgs-phoenix/app_unreal/Binaries/Mac/libmetalirconverter.dylib" "$APP_BUNDLE/Contents/Frameworks/libmetalirconverter.dylib"
cp "/Users/perkunas/jail/3dgs-phoenix/app_unreal/Binaries/Mac/libmetalirconverter.dylib" "$APP_BUNDLE/Contents/Resources/libmetalirconverter.dylib"

echo "=== 5. Packaging into .dmg Installer ==="
hdiutil create -volname "3DGS-Phoenix" -srcfolder "$APP_BUNDLE" -ov -format UDZO "/Users/perkunas/jail/3dgs-phoenix/app_flutter/build/macos/Build/Products/Release/3DGS-Phoenix.dmg"
echo "=== Packaging Complete ==="
