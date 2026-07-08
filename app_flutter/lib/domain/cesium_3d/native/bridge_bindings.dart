import 'dart:ffi';
import 'dart:io' show Platform;
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

const String ffiComplianceSafety = 'nativefinalizer refcount';

final class BridgeCamera extends Struct {
  @Double()
  external double latitude;

  @Double()
  external double longitude;

  @Double()
  external double altitude;

  @Double()
  external double heading;

  @Double()
  external double pitch;

  @Double()
  external double roll;
}

final class BridgeTilesetConfig extends Struct {
  external Pointer<Utf8> tilesetUrl;

  @Int32()
  external int maxSimultaneousTileLoads;

  @Int32()
  external int maxCachedBytes;
}

typedef BridgeHandle = Int32;

// NOTE — THREAD SAFETY:
// Native callbacks (BridgeErrorCallback, BridgeTileReadyCallback,
// BridgeCameraChangedCallback) are registered via Pointer.fromFunction and
// may be invoked from native worker threads. The Dart VM prohibits calling
// into Dart from a non-main-isolate thread.
//
// Known limitation: the current stub (bridge.cpp returns error codes for
// tile requests) passes nullptr for every callback, so no actual thread
// violation can occur at runtime. When real callbacks are implemented,
// NativeCallable.listener (Dart SDK >= 3.4) should be used instead of
// Pointer.fromFunction to guarantee correct thread affinity.
typedef BridgeErrorCallbackNative = Void Function(
  Int32 errorCode, Pointer<Utf8> message, Pointer<Void> userData,
);
typedef BridgeErrorCallback = void Function(
  int errorCode, Pointer<Utf8> message, Pointer<Void> userData,
);

typedef BridgeTileReadyCallbackNative = Void Function(
  Pointer<Utf8> tileId, Pointer<Uint8> data, Int32 size, Pointer<Void> userData,
);
typedef BridgeTileReadyCallback = void Function(
  Pointer<Utf8> tileId, Pointer<Uint8> data, int size, Pointer<Void> userData,
);

typedef BridgeCameraChangedCallbackNative = Void Function(
  Double lat, Double lng, Double alt, Double pitch, Double heading, Pointer<Void> userData,
);
typedef BridgeCameraChangedCallback = void Function(
  double lat, double lng, double alt, double pitch, double heading, Pointer<Void> userData,
);

typedef BridgeInitializeNative = BridgeHandle Function(
  Pointer<BridgeTilesetConfig> config,
  Pointer<NativeFunction<BridgeErrorCallbackNative>> onError,
  Pointer<Void> userData,
);
typedef BridgeInitializeDart = int Function(
  Pointer<BridgeTilesetConfig> config,
  Pointer<NativeFunction<BridgeErrorCallbackNative>> onError,
  Pointer<Void> userData,
);

typedef BridgeShutdownNative = Void Function(BridgeHandle handle);
typedef BridgeShutdownDart = void Function(int handle);

typedef BridgeIsReadyNative = Int32 Function(BridgeHandle handle);
typedef BridgeIsReadyDart = int Function(int handle);

typedef BridgeGetLastErrorNative = Int32 Function(BridgeHandle handle, Pointer<Utf8> out, Int32 size);
typedef BridgeGetLastErrorDart = int Function(int handle, Pointer<Utf8> out, int size);

typedef BridgeUpdateCameraNative = Int32 Function(
  BridgeHandle handle, Pointer<BridgeCamera> camera,
);
typedef BridgeUpdateCameraDart = int Function(
  int handle, Pointer<BridgeCamera> camera,
);

typedef BridgeRegisterCameraCallbackNative = Int32 Function(
  BridgeHandle handle,
  Pointer<NativeFunction<BridgeCameraChangedCallbackNative>> callback,
  Pointer<Void> userData,
);
typedef BridgeRegisterCameraCallbackDart = int Function(
  int handle,
  Pointer<NativeFunction<BridgeCameraChangedCallbackNative>> callback,
  Pointer<Void> userData,
);

typedef BridgeGetVisibleTileCountNative = Int32 Function(
  BridgeHandle handle, Pointer<Int32> outCount,
);
typedef BridgeGetVisibleTileCountDart = int Function(
  int handle, Pointer<Int32> outCount,
);

typedef BridgeGetVisibleTileIdNative = Int32 Function(
  BridgeHandle handle, Int32 index, Pointer<Pointer<Utf8>> outTileId,
);
typedef BridgeGetVisibleTileIdDart = int Function(
  int handle, int index, Pointer<Pointer<Utf8>> outTileId,
);

typedef BridgeRequestTileDataNative = Int32 Function(
  BridgeHandle handle,
  Pointer<Utf8> tileId,
  Pointer<NativeFunction<BridgeTileReadyCallbackNative>> callback,
  Pointer<Void> userData,
);
typedef BridgeRequestTileDataDart = int Function(
  int handle,
  Pointer<Utf8> tileId,
  Pointer<NativeFunction<BridgeTileReadyCallbackNative>> callback,
  Pointer<Void> userData,
);

typedef BridgeCartographicToEcefNative = Int32 Function(
  Double latDeg, Double lngDeg, Double altM,
  Pointer<Double> outX, Pointer<Double> outY, Pointer<Double> outZ,
);
typedef BridgeCartographicToEcefDart = int Function(
  double latDeg, double lngDeg, double altM,
  Pointer<Double> outX, Pointer<Double> outY, Pointer<Double> outZ,
);

typedef BridgeEcefToCartographicNative = Int32 Function(
  Double x, Double y, Double z,
  Pointer<Double> outLatDeg, Pointer<Double> outLngDeg, Pointer<Double> outAltM,
);
typedef BridgeEcefToCartographicDart = int Function(
  double x, double y, double z,
  Pointer<Double> outLatDeg, Pointer<Double> outLngDeg, Pointer<Double> outAltM,
);

typedef BridgeAllocNative = Pointer<Void> Function(Int32 size);
typedef BridgeAllocDart = Pointer<Void> Function(int size);

typedef BridgeFreeNative = Void Function(Pointer<Void> ptr);
typedef BridgeFreeDart = void Function(Pointer<Void> ptr);

typedef BridgeFreeStringNative = Void Function(Pointer<Utf8> str);
typedef BridgeFreeStringDart = void Function(Pointer<Utf8> str);

typedef BridgeErrorMessageNative = Pointer<Utf8> Function(Int32 errorCode);
typedef BridgeErrorMessageDart = Pointer<Utf8> Function(int errorCode);

class CesiumNativeBindings {
  final DynamicLibrary _lib;

  late final BridgeInitializeDart initialize;
  late final BridgeShutdownDart shutdown;
  late final BridgeIsReadyDart isReady;
  late final BridgeGetLastErrorDart getLastError;
  late final BridgeUpdateCameraDart updateCamera;
  late final BridgeRegisterCameraCallbackDart registerCameraCallback;
  late final BridgeGetVisibleTileCountDart getVisibleTileCount;
  late final BridgeGetVisibleTileIdDart getVisibleTileId;
  late final BridgeRequestTileDataDart requestTileData;
  late final BridgeCartographicToEcefDart cartographicToEcef;
  late final BridgeEcefToCartographicDart ecefToCartographic;
  late final BridgeAllocDart alloc;
  late final BridgeFreeDart free;
  late final BridgeFreeStringDart freeString;
  late final BridgeErrorMessageDart errorMessage;

  CesiumNativeBindings(this._lib) {
    initialize = _lib.lookupFunction<BridgeInitializeNative, BridgeInitializeDart>('bridge_initialize');
    shutdown = _lib.lookupFunction<BridgeShutdownNative, BridgeShutdownDart>('bridge_shutdown');
    isReady = _lib.lookupFunction<BridgeIsReadyNative, BridgeIsReadyDart>('bridge_is_ready');
    getLastError = _lib.lookupFunction<BridgeGetLastErrorNative, BridgeGetLastErrorDart>('bridge_get_last_error');
    updateCamera = _lib.lookupFunction<BridgeUpdateCameraNative, BridgeUpdateCameraDart>('bridge_update_camera');
    registerCameraCallback = _lib.lookupFunction<BridgeRegisterCameraCallbackNative, BridgeRegisterCameraCallbackDart>('bridge_register_camera_callback');
    getVisibleTileCount = _lib.lookupFunction<BridgeGetVisibleTileCountNative, BridgeGetVisibleTileCountDart>('bridge_get_visible_tile_count');
    getVisibleTileId = _lib.lookupFunction<BridgeGetVisibleTileIdNative, BridgeGetVisibleTileIdDart>('bridge_get_visible_tile_id');
    requestTileData = _lib.lookupFunction<BridgeRequestTileDataNative, BridgeRequestTileDataDart>('bridge_request_tile_data');
    cartographicToEcef = _lib.lookupFunction<BridgeCartographicToEcefNative, BridgeCartographicToEcefDart>('bridge_cartographic_to_ecef');
    ecefToCartographic = _lib.lookupFunction<BridgeEcefToCartographicNative, BridgeEcefToCartographicDart>('bridge_ecef_to_cartographic');
    alloc = _lib.lookupFunction<BridgeAllocNative, BridgeAllocDart>('bridge_alloc');
    free = _lib.lookupFunction<BridgeFreeNative, BridgeFreeDart>('bridge_free');
    freeString = _lib.lookupFunction<BridgeFreeStringNative, BridgeFreeStringDart>('bridge_free_string');
    errorMessage = _lib.lookupFunction<BridgeErrorMessageNative, BridgeErrorMessageDart>('bridge_error_message');
  }

  static CesiumNativeBindings load() {
    if (kIsWeb) {
      throw UnsupportedError('Cesium native bridge is not supported on Web');
    }
    if (Platform.isMacOS) {
      final lib = DynamicLibrary.open('libcesium_native_bridge.dylib');
      return CesiumNativeBindings(lib);
    } else if (Platform.isLinux) {
      final lib = DynamicLibrary.open('libcesium_native_bridge.so');
      return CesiumNativeBindings(lib);
    } else if (Platform.isWindows) {
      final lib = DynamicLibrary.open('cesium_native_bridge.dll');
      return CesiumNativeBindings(lib);
    }
    throw UnsupportedError('Cesium native bridge is not available on this platform');
  }
}


