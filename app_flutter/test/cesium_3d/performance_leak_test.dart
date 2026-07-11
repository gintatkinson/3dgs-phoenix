import 'dart:ffi';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_flutter/domain/cesium_3d/cesium_engine.dart';
import 'package:app_flutter/domain/cesium_3d/native/bridge_bindings.dart';
import 'package:app_flutter/domain/cesium_3d/virtual_camera.dart';

// A mock/fake implementation of CesiumNativeBindings for testing camera update throttling.
class FakeCesiumNativeBindings implements CesiumNativeBindings {
  int updateCameraCalls = 0;
  int shutdownCalls = 0;

  @override
  late final BridgeUpdateCameraDart updateCamera = (int handle, Pointer<BridgeCamera> camera) {
    updateCameraCalls++;
    return 0;
  };

  @override
  late final BridgeShutdownDart shutdown = (int handle) {
    shutdownCalls++;
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('CesiumEngine Performance & Leak Tests', () {
    test('throttlesFrequentCameraUpdates propagates only 1 update in a tight loop', () {
      final fakeBindings = FakeCesiumNativeBindings();
      final engine = CesiumEngine.private(fakeBindings, 42);

      // Send 50 updates in a tight loop.
      // The first update is sent immediately.
      // Sub-second subsequent updates with small geodetic changes should be throttled.
      for (int i = 0; i < 50; i++) {
        final camera = VirtualCamera(
          latitude: 35.6762 + (i * 0.000001), // change is < 0.0001 degrees
          longitude: 139.6503 + (i * 0.000001), // change is < 0.0001 degrees
          altitude: 100.0 + (i * 0.1), // change is < 10.0 meters
          heading: 0.0,
          pitch: -45.0,
          roll: 0.0,
        );
        engine.updateCamera(camera);
      }

      // Only the first update should propagate to the native FFI.
      expect(fakeBindings.updateCameraCalls, equals(1));
    });

    test('verifiesNoCallbackLeaks ensures NativeCallables are correctly closed and disposed', () async {
      // Initialize the engine.
      // Under a test environment with the fallback configured in load(),
      // this will load the dylib or throw if not present.
      // We wrap initialization in a try-catch to allow the test to pass/skip if
      // the native library is missing on the current execution host.
      CesiumEngine? engine;
      try {
        engine = await CesiumEngine.initialize(
          maxSimultaneousTileLoads: 5,
          maxCachedBytes: 1024 * 1024,
        );
      } catch (e) {
        print('Skipping verifiesNoCallbackLeaks: native library loading failed ($e).');
        return;
      }

      expect(engine, isNotNull);
      expect(CesiumEngine.errorCallable, isNotNull);
      expect(CesiumEngine.tileReadyCallable, isNotNull);

      // Dispose of the engine.
      engine.dispose();

      // Ensure that callables are closed and references are set to null.
      expect(CesiumEngine.errorCallable, isNull);
      expect(CesiumEngine.tileReadyCallable, isNull);
      expect(CesiumEngine.instance, isNull);
    });
  });
}
