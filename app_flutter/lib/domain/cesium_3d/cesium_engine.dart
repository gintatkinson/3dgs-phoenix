import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';
import 'package:app_flutter/domain/cesium_3d/native/bridge_bindings.dart';
import 'package:app_flutter/domain/cesium_3d/native/error_handler.dart';
import 'package:app_flutter/domain/cesium_3d/virtual_camera.dart';

/// Core controller class for the Cesium 3D Terrain engine, managing the native FFI lifecycle,
/// camera updates, and coordinate transformations.
class CesiumEngine {
  final CesiumNativeBindings _bindings;
  final int _handle;

  DateTime? _lastUpdateTime;
  double? _lastLatitude;
  double? _lastLongitude;
  double? _lastAltitude;

  CesiumEngine._(this._bindings, this._handle);

  /// Constructor for testing purposes to inject mock bindings.
  @visibleForTesting
  CesiumEngine.private(this._bindings, this._handle);

  static CesiumEngine? _instance;

  static NativeCallable<BridgeErrorCallbackNative>? _errorCallable;
  static NativeCallable<BridgeTileReadyCallbackNative>? _tileReadyCallable;

  /// Access the internal error callback NativeCallable for memory leak validation.
  @visibleForTesting
  static NativeCallable<BridgeErrorCallbackNative>? get errorCallable => _errorCallable;

  /// Access the internal tile ready callback NativeCallable for memory leak validation.
  @visibleForTesting
  static NativeCallable<BridgeTileReadyCallbackNative>? get tileReadyCallable => _tileReadyCallable;

  static final Map<String, void Function(Uint8List data)> _pendingTileCallbacks = {};

  static void _onNativeError(int errorCode, Pointer<Utf8> message, Pointer<Void> userData) {
    final msg = message.toDartString();
    print('Native Error ($errorCode): $msg');
  }

  static void _onTileReady(Pointer<Utf8> tileIdPtr, Pointer<Uint8> dataPtr, int size, Pointer<Void> userData) {
    final tileId = tileIdPtr.toDartString();
    final callback = _pendingTileCallbacks.remove(tileId);
    if (callback != null) {
      final list = dataPtr.asTypedList(size);
      final data = Uint8List.fromList(list);
      callback(data);
    }
  }

  /// Initializes the Cesium 3D Engine.
  ///
  /// Optionally configures a [tilesetUrl], [maxSimultaneousTileLoads], and [maxCachedBytes].
  /// Automatically disposes of any existing instance before initializing a new one.
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

    _errorCallable?.close();
    _errorCallable = NativeCallable<BridgeErrorCallbackNative>.listener(_onNativeError);

    _tileReadyCallable?.close();
    _tileReadyCallable = NativeCallable<BridgeTileReadyCallbackNative>.listener(_onTileReady);

    final handle = bindings.initialize(config, _errorCallable!.nativeFunction, nullptr);

    if (tilesetUrl != null && tilesetUrl.isNotEmpty) {
      calloc.free(config.ref.tilesetUrl);
    }
    calloc.free(config);

    checkStatus(handle);

    final engine = CesiumEngine._(bindings, handle);
    _instance = engine;
    return engine;
  }

  /// Gets the currently active [CesiumEngine] instance, or null if not initialized.
  static CesiumEngine? get instance => _instance;

  /// Returns true if the native Cesium tileset is ready for rendering.
  bool get isReady {
    return _bindings.isReady(_handle) != 0;
  }

  /// Updates the native camera state with the specified [camera] parameters.
  ///
  /// Camera updates are throttled: if the elapsed time since the last update
  /// is less than 100 milliseconds and the geodetic delta is small (latitude change
  /// < 0.0001 degrees, longitude change < 0.0001 degrees, and altitude change
  /// < 10.0 meters), the update is discarded to save processing overhead.
  void updateCamera(VirtualCamera camera) {
    final now = DateTime.now();
    if (_lastUpdateTime != null) {
      final elapsedMs = now.difference(_lastUpdateTime!).inMilliseconds;
      if (elapsedMs < 100) {
        final deltaLat = (camera.latitude - _lastLatitude!).abs();
        final deltaLng = (camera.longitude - _lastLongitude!).abs();
        final deltaAlt = (camera.altitude - _lastAltitude!).abs();
        if (deltaLat < 0.0001 && deltaLng < 0.0001 && deltaAlt < 10.0) {
          return;
        }
      }
    }

    _lastUpdateTime = now;
    _lastLatitude = camera.latitude;
    _lastLongitude = camera.longitude;
    _lastAltitude = camera.altitude;

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

  /// Returns the number of currently visible tiles in the viewport.
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

  /// Returns the ID of the visible tile at the specified [index], or null if invalid.
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

  /// Returns a list of all currently visible tile IDs.
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

  /// Converts geodetic cartographic coordinates ([latDeg] latitude in degrees,
  /// [lngDeg] longitude in degrees, [altM] altitude in meters) to ECEF (Earth-Centered,
  /// Earth-Fixed) Cartesian (X, Y, Z) coordinates.
  ///
  /// Returns a 3-tuple of (X, Y, Z) or null if the native call fails.
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

  /// Converts ECEF Cartesian coordinates ([x], [y], [z]) to geodetic cartographic
  /// coordinates (latitude in degrees, longitude in degrees, altitude in meters).
  ///
  /// Returns a 3-tuple of (latitude, longitude, altitude) or null if the native call fails.
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

  /// Requests the raw imagery/terrain data for the specified [tileId], registering
  /// the [onReady] callback to be invoked when the data is loaded.
  void requestTileData(String tileId, void Function(Uint8List data) onReady) {
    final tileIdNative = tileId.toNativeUtf8(allocator: calloc);
    _pendingTileCallbacks[tileId] = onReady;
    _bindings.requestTileData(
      _handle,
      tileIdNative,
      _tileReadyCallable?.nativeFunction ?? nullptr,
      nullptr,
    );
    calloc.free(tileIdNative);
  }

  /// Disposes of the engine, shutting down the native Cesium systems and closing
  /// active FFI callbacks.
  void dispose() {
    _bindings.shutdown(_handle);
    _errorCallable?.close();
    _errorCallable = null;
    _tileReadyCallable?.close();
    _tileReadyCallable = null;
    _pendingTileCallbacks.clear();
    if (_instance == this) {
      _instance = null;
    }
  }
}
