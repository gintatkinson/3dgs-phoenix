#!/bin/bash
set -e
echo "=== 1. Building Flutter macOS App in Release Mode ==="
cd /Users/perkunas/jail/3dgs-phoenix/app_flutter
flutter build macos --release

echo "=== 2. Creating Resources Directories inside App Bundle ==="
APP_BUNDLE="/Users/perkunas/jail/3dgs-phoenix/app_flutter/build/macos/Build/Products/Release/app_flutter.app"
mkdir -p "$APP_BUNDLE/Contents/Resources/Binaries/Mac"
mkdir -p "$APP_BUNDLE/Contents/Resources/Saved/Cooked"

echo "=== 3. Copying Unreal Daemon Binary ==="
cp "/Users/perkunas/jail/3dgs-phoenix/app_unreal/Binaries/Mac/cesium_daemon" "$APP_BUNDLE/Contents/Resources/Binaries/Mac/cesium_daemon"

echo "=== 4. Copying Cooked Assets ==="
cp -R "/Users/perkunas/jail/3dgs-phoenix/app_unreal/Saved/Cooked/Mac" "$APP_BUNDLE/Contents/Resources/Saved/Cooked/Mac"

echo "=== 5. Copying Dependent Shared Libraries ==="
cp "/Users/perkunas/jail/3dgs-phoenix/app_unreal/Binaries/Mac/libmetalirconverter.dylib" "$APP_BUNDLE/Contents/Frameworks/libmetalirconverter.dylib"
cp "/Users/perkunas/jail/3dgs-phoenix/app_unreal/Binaries/Mac/libmetalirconverter.dylib" "$APP_BUNDLE/Contents/Resources/Binaries/Mac/libmetalirconverter.dylib"
cp "/Users/perkunas/jail/3dgs-phoenix/app_unreal/Binaries/Mac/libtbb.12.dylib" "$APP_BUNDLE/Contents/Frameworks/libtbb.12.dylib"
cp "/Users/perkunas/jail/3dgs-phoenix/app_unreal/Binaries/Mac/libtbb.12.dylib" "$APP_BUNDLE/Contents/Resources/Binaries/Mac/libtbb.12.dylib"

echo "=== 6. Packaging into .dmg Installer ==="
hdiutil create -volname "3DGS-Phoenix" -srcfolder "$APP_BUNDLE" -ov -format UDZO "/Users/perkunas/jail/3dgs-phoenix/app_flutter/build/macos/Build/Products/Release/3DGS-Phoenix.dmg"
echo "=== Packaging Complete ==="
