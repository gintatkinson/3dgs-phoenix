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
rm -f "$APP_BUNDLE/Contents/Resources/Binaries/Mac/cesium_daemon"
cp "/Users/perkunas/jail/3dgs-phoenix/app_unreal/Binaries/Mac/cesium_daemon" "$APP_BUNDLE/Contents/Resources/Binaries/Mac/cesium_daemon"

echo "=== 4. Copying Cooked Assets ==="
rm -rf "$APP_BUNDLE/Contents/Resources/Saved/Cooked/Mac"
cp -R "/Users/perkunas/jail/3dgs-phoenix/app_unreal/Saved/Cooked/Mac" "$APP_BUNDLE/Contents/Resources/Saved/Cooked/Mac"

echo "=== 5. Copying Dependent Shared Libraries ==="
rm -f "$APP_BUNDLE/Contents/Frameworks/libmetalirconverter.dylib"
cp "/Users/perkunas/jail/3dgs-phoenix/app_unreal/Binaries/Mac/libmetalirconverter.dylib" "$APP_BUNDLE/Contents/Frameworks/libmetalirconverter.dylib"

rm -f "$APP_BUNDLE/Contents/Resources/Binaries/Mac/libmetalirconverter.dylib"
cp "/Users/perkunas/jail/3dgs-phoenix/app_unreal/Binaries/Mac/libmetalirconverter.dylib" "$APP_BUNDLE/Contents/Resources/Binaries/Mac/libmetalirconverter.dylib"

rm -f "$APP_BUNDLE/Contents/Frameworks/libtbb.12.dylib"
cp "/Users/perkunas/jail/3dgs-phoenix/app_unreal/Binaries/Mac/libtbb.12.dylib" "$APP_BUNDLE/Contents/Frameworks/libtbb.12.dylib"

rm -f "$APP_BUNDLE/Contents/Resources/Binaries/Mac/libtbb.12.dylib"
cp "/Users/perkunas/jail/3dgs-phoenix/app_unreal/Binaries/Mac/libtbb.12.dylib" "$APP_BUNDLE/Contents/Resources/Binaries/Mac/libtbb.12.dylib"

echo "=== 6. Codesigning Helper Executables and Libraries ==="
codesign --force -s - "$APP_BUNDLE/Contents/Frameworks/libmetalirconverter.dylib"
codesign --force -s - "$APP_BUNDLE/Contents/Resources/Binaries/Mac/libmetalirconverter.dylib"
codesign --force -s - "$APP_BUNDLE/Contents/Frameworks/libtbb.12.dylib"
codesign --force -s - "$APP_BUNDLE/Contents/Resources/Binaries/Mac/libtbb.12.dylib"
codesign --force -s - "$APP_BUNDLE/Contents/Resources/Binaries/Mac/cesium_daemon"

echo "=== 7. Packaging into .dmg Installer ==="
hdiutil create -volname "3DGS-Phoenix" -srcfolder "$APP_BUNDLE" -ov -format UDZO "/Users/perkunas/jail/3dgs-phoenix/app_flutter/build/macos/Build/Products/Release/3DGS-Phoenix.dmg"
echo "=== Packaging Complete ==="
