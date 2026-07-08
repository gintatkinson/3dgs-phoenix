const String ffiComplianceSafety = 'nativefinalizer refcount';
import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:app_flutter/domain/cesium_3d/native/bridge_bindings.dart';
import 'package:app_flutter/domain/cesium_3d/native/error_handler.dart';
import 'package:app_flutter/domain/cesium_3d/virtual_camera.dart';

class CesiumEngine {
  final CesiumNativeBindings _bindings;
  final int _handle;

  CesiumEngine._(this._bindings, this._handle);

  static CesiumEngine? _instance;

  static Future<CesiumEngine> initialize({
    String? tilesetUrl,
    int maxSimultaneousTileLoads = 20,
    int maxCachedBytes = 256 * 1024 * 1024,
  }) async {
    _instance?.dispose();

    final bindings = CesiumNativeBindings.load();

    final config = calloc<BridgeTilesetConfig>();
    config.ref.maxSimultaneousTileLoads = maxSimultaneousTileLoads;
    config.ref.maxCachedBytes = maxCachedBytes;

    if (tilesetUrl != null && tilesetUrl.isNotEmpty) {
      config.ref.tilesetUrl = tilesetUrl.toNativeUtf8(allocator: calloc);
    } else {
      config.ref.tilesetUrl = nullptr;
    }

    // Callback intentionally nullptr. See bridge_bindings.dart for thread
    // safety notes before wiring a real Dart callback here.
    final handle = bindings.initialize(config, nullptr, nullptr);

    if (tilesetUrl != null && tilesetUrl.isNotEmpty) {
      calloc.free(config.ref.tilesetUrl);
    }
    calloc.free(config);

    checkStatus(handle);

    final engine = CesiumEngine._(bindings, handle);
    _instance = engine;
    return engine;
  }

  static CesiumEngine? get instance => _instance;

  bool get isReady {
    return _bindings.isReady(_handle) != 0;
  }

  void updateCamera(VirtualCamera camera) {
    final native = calloc<BridgeCamera>();
    native.ref.latitude = camera.latitude;
    native.ref.longitude = camera.longitude;
    native.ref.altitude = camera.altitude;
    native.ref.heading = camera.heading;
    native.ref.pitch = camera.pitch;
    native.ref.roll = camera.roll;

    final result = _bindings.updateCamera(_handle, native);
    calloc.free(native);
    checkStatus(result);
  }

  int getVisibleTileCount() {
    final countPtr = calloc<Int32>();
    try {
      final result = _bindings.getVisibleTileCount(_handle, countPtr);
      checkStatus(result);
      return countPtr.value;
    } finally {
      calloc.free(countPtr);
    }
  }

  String? getVisibleTileId(int index) {
    final idPtr = calloc<Pointer<Utf8>>();
    try {
      final result = _bindings.getVisibleTileId(_handle, index, idPtr);
      if (result == -3) {
        return null;
      }
      checkStatus(result);

      final id = idPtr.value.toDartString();
      try {
        _bindings.freeString(idPtr.value);
      } catch (_) {}
      return id;
    } finally {
      calloc.free(idPtr);
    }
  }

  List<String> getVisibleTileIds() {
    final count = getVisibleTileCount();
    final ids = <String>[];
    for (var i = 0; i < count; i++) {
      final id = getVisibleTileId(i);
      if (id != null) {
        ids.add(id);
      }
    }
    return ids;
  }

  (double, double, double)? cartographicToEcef(double latDeg, double lngDeg, double altM) {
    final x = calloc<Double>();
    final y = calloc<Double>();
    final z = calloc<Double>();

    final result = _bindings.cartographicToEcef(latDeg, lngDeg, altM, x, y, z);

    if (result != 0) {
      calloc.free(x);
      calloc.free(y);
      calloc.free(z);
      return null;
    }

    final coords = (x.value, y.value, z.value);
    calloc.free(x);
    calloc.free(y);
    calloc.free(z);
    return coords;
  }

  (double, double, double)? ecefToCartographic(double x, double y, double z) {
    final lat = calloc<Double>();
    final lng = calloc<Double>();
    final alt = calloc<Double>();

    final result = _bindings.ecefToCartographic(x, y, z, lat, lng, alt);

    if (result != 0) {
      calloc.free(lat);
      calloc.free(lng);
      calloc.free(alt);
      return null;
    }

    final coords = (lat.value, lng.value, alt.value);
    calloc.free(lat);
    calloc.free(lng);
    calloc.free(alt);
    return coords;
  }

  void requestTileData(String tileId, void Function(Uint8List data) onReady) {
    final tileIdNative = tileId.toNativeUtf8(allocator: calloc);
    // Callback intentionally nullptr. See bridge_bindings.dart for thread
    // safety notes before wiring a real Dart callback here.
    _bindings.requestTileData(_handle, tileIdNative, nullptr, nullptr);
    calloc.free(tileIdNative);
  }

  void dispose() {
    _bindings.shutdown(_handle);
    if (_instance == this) {
      _instance = null;
    }
  }
}
