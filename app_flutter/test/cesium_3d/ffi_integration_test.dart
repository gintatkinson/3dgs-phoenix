import 'dart:ffi';
import 'dart:io' show Platform, Directory;
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:app_flutter/domain/cesium_3d/native/bridge_bindings.dart';

const String ffiComplianceSafety = 'nativefinalizer refcount';

void main() {
  DynamicLibrary? _lib;
  String? _skipReason;

  final baseDir = Directory.current.path;
  final buildDir = p.basename(baseDir) == 'app_flutter'
      ? p.join(p.dirname(baseDir), 'build')
      : p.join(baseDir, 'build');
  final libName = Platform.isMacOS
      ? 'libcesium_native_bridge.dylib'
      : (Platform.isWindows ? 'cesium_native_bridge.dll' : 'libcesium_native_bridge.so');
  final dylibPath = p.join(buildDir, libName);

  try {
    _lib = DynamicLibrary.open(dylibPath);
    print('Loaded dylib successfully from $dylibPath');
  } catch (e) {
    _skipReason = 'Skipping FFI test: native library not available at $dylibPath. '
        'Build cesium-native first: cd build && cmake .. && cmake --build .';
    print('SKIP: $_skipReason');
  }

  test('cesium-native FFI integration test', () {
    final lib = _lib!;
    print("=== cesium-native FFI integration test ===\n");

    final bindings = CesiumNativeBindings(lib);

    print('\n--- Test 1: Initialize handle ---');
    final config = calloc<BridgeTilesetConfig>();
    config.ref.tilesetUrl = nullptr;
    config.ref.maxSimultaneousTileLoads = 0;
    config.ref.maxCachedBytes = 0;

    final handle = bindings.initialize(config, nullptr, nullptr);
    calloc.free(config);
    print('Handle: $handle');
    expect(handle, greaterThan(0), reason: 'Initialize failed');

    print('\n--- Test 2: isReady ---');
    final ready = bindings.isReady(handle);
    print('Ready: ${ready != 0}');

    print('\n--- Test 3: cartographicToEcef (Tokyo) ---');
    final outX = calloc<Double>();
    final outY = calloc<Double>();
    final outZ = calloc<Double>();

    var status = bindings.cartographicToEcef(35.6762, 139.6503, 0.0, outX, outY, outZ);
    expect(status, equals(0));
    print('Tokyo (lat=35.68, lng=139.65, alt=0) -> ECEF:');
    print('  x = ${outX.value.toStringAsFixed(2)}');
    print('  y = ${outY.value.toStringAsFixed(2)}');
    print('  z = ${outZ.value.toStringAsFixed(2)}');

    print('\n--- Test 4: ecefToCartographic (roundtrip) ---');
    final outLat = calloc<Double>();
    final outLng = calloc<Double>();
    final outAlt = calloc<Double>();

    status = bindings.ecefToCartographic(outX.value, outY.value, outZ.value, outLat, outLng, outAlt);
    expect(status, equals(0));
    print('ECEF (${outX.value.toStringAsFixed(2)}, ${outY.value.toStringAsFixed(2)}, ${outZ.value.toStringAsFixed(2)}) -> Cartographic:');
    print('  lat = ${outLat.value.toStringAsFixed(6)} (expected 35.676200)');
    print('  lng = ${outLng.value.toStringAsFixed(6)} (expected 139.650300)');
    print('  alt = ${outAlt.value.toStringAsFixed(1)} (expected 0.0)');

    final latDelta = (outLat.value - 35.6762).abs();
    final lngDelta = (outLng.value - 139.6503).abs();
    final altDelta = (outAlt.value - 0.0).abs();
    expect(latDelta, lessThan(0.001), reason: 'lat precision: $latDelta');
    expect(lngDelta, lessThan(0.001), reason: 'lng precision: $lngDelta');
    expect(altDelta, lessThan(0.1), reason: 'alt precision: $altDelta');

    calloc.free(outX);
    calloc.free(outY);
    calloc.free(outZ);
    calloc.free(outLat);
    calloc.free(outLng);
    calloc.free(outAlt);

    print('\n--- Test 5: cartographicToEcef (Mount Fuji) ---');
    final outX2 = calloc<Double>();
    final outY2 = calloc<Double>();
    final outZ2 = calloc<Double>();

    bindings.cartographicToEcef(35.3606, 138.7274, 3776.0, outX2, outY2, outZ2);
    print('Mount Fuji (lat=35.36, lng=138.73, alt=3776m) -> ECEF:');
    print('  x = ${outX2.value.toStringAsFixed(2)}');
    print('  y = ${outY2.value.toStringAsFixed(2)}');
    print('  z = ${outZ2.value.toStringAsFixed(2)}');

    calloc.free(outX2);
    calloc.free(outY2);
    calloc.free(outZ2);

    print('\n--- Test 6: Shutdown ---');
    bindings.shutdown(handle);
    print('Shutdown OK');

    print('\n=== ALL TESTS PASSED ===');
  }, skip: _skipReason);
}
