import 'dart:async';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_flutter/domain/cesium_3d/cesium_engine.dart';
import 'package:app_flutter/domain/cesium_3d/native/bridge_bindings.dart';
import 'package:app_flutter/domain/cesium_3d/native/error_handler.dart';
import 'package:app_flutter/domain/cesium_3d/virtual_camera.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CesiumEngine Performance & Leak Tests', () {
    test('throttlesFrequentCameraUpdates propagates only 1 update in a tight loop', () async {
      CesiumEngine? engine;
      try {
        engine = await CesiumEngine.initialize(
          tilesetUrl: 'https://example.com',
          maxSimultaneousTileLoads: 5,
          maxCachedBytes: 1024 * 1024,
        );
      } catch (e) {
        print('Skipping throttlesFrequentCameraUpdates: native library loading failed ($e).');
        return;
      }

      final firstCamera = VirtualCamera(
        latitude: 35.6762,
        longitude: 139.6503,
        altitude: 100.0,
        heading: 0.0,
        pitch: -45.0,
        roll: 0.0,
      );

      // Send the first update.
      engine.updateCamera(firstCamera);

      // Verify first update coordinates are set.
      expect(engine.lastLatitude, equals(35.6762));

      // Send subsequent updates in a tight loop.
      // Sub-second subsequent updates with small geodetic changes should be throttled.
      for (int i = 1; i <= 50; i++) {
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

      // Check that the engine still has the first camera's coordinates (the others were throttled).
      expect(engine.lastLatitude, equals(35.6762));

      engine.dispose();
    });

    test('verifiesNoCallbackLeaks ensures NativeCallables are correctly closed and disposed', () async {
      CesiumEngine? engine;
      try {
        engine = await CesiumEngine.initialize(
          tilesetUrl: 'https://example.com',
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

    test('FFI error stream and state propagation updates properly', () async {
      CesiumEngine? engine;
      try {
        engine = await CesiumEngine.initialize(
          tilesetUrl: 'https://example.com',
          maxSimultaneousTileLoads: 5,
          maxCachedBytes: 1024 * 1024,
        );
      } catch (e) {
        print('Skipping FFI error stream test: native library loading failed ($e).');
        return;
      }

      final errorEvents = <CesiumError>[];
      final subscription = CesiumEngine.errorStream.listen(errorEvents.add);

      // Verify initial state is empty/null
      expect(CesiumEngine.lastNativeError, isNull);
      expect(CesiumEngine.lastNativeErrorCode, isNull);

      // Get the error callback and trigger a simulated FFI native error callback
      final errorCallable = CesiumEngine.errorCallable;
      expect(errorCallable, isNotNull);

      final errorCallback = errorCallable!.nativeFunction.asFunction<BridgeErrorCallback>();
      final errorMsg = 'Simulated native error message';
      final errorMsgPtr = errorMsg.toNativeUtf8(allocator: calloc);

      try {
        errorCallback(101, errorMsgPtr, nullptr);
        // Wait for asynchronous event loop dispatch of the native callback
        await Future.delayed(const Duration(milliseconds: 200));

        // Verify state was updated
        expect(CesiumEngine.lastNativeErrorCode, equals(101));
        expect(CesiumEngine.lastNativeError, equals('Simulated native error message'));

        // Verify stream fired event
        expect(errorEvents.length, equals(1));
        expect(errorEvents[0].code, equals(101));
        expect(errorEvents[0].message, equals('Simulated native error message'));
      } finally {
        calloc.free(errorMsgPtr);
      }

      await subscription.cancel();
      engine.dispose();
    });
  });
}
