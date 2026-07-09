import 'package:flutter_test/flutter_test.dart';
import 'package:app_flutter/domain/cesium_3d/native/windows_dxgi_bridge.dart';

void main() {
  group('Windows DXGI Texture Interop Tests', () {
    test('createSharedHandle validates width and height constraints', () {
      const bridge = WindowsDxgiBridge();

      // Valid width and height should succeed and return mock handle value.
      final handle = bridge.createSharedHandle(1920, 1080);
      expect(handle, equals(2588));

      // Invalid width or height <= 0 should throw SurfaceBindingFailure.
      expect(() => bridge.createSharedHandle(0, 1080), throwsA(isA<SurfaceBindingFailure>()));
      expect(() => bridge.createSharedHandle(1920, 0), throwsA(isA<SurfaceBindingFailure>()));
      expect(() => bridge.createSharedHandle(-1, 1080), throwsA(isA<SurfaceBindingFailure>()));
      expect(() => bridge.createSharedHandle(1920, -5), throwsA(isA<SurfaceBindingFailure>()));
    });

    test('registerDxgiSurface validates handle constraints', () {
      const bridge = WindowsDxgiBridge();

      // Valid handle should succeed.
      expect(bridge.registerDxgiSurface(2588), isTrue);

      // Zero handle should throw InvalidDxgiHandle.
      expect(() => bridge.registerDxgiSurface(0), throwsA(isA<InvalidDxgiHandle>()));
    });

    test('FlutterWindowsEmbedder validates handle and matches surfaceType', () {
      const embedder = FlutterWindowsEmbedder(surfaceType: 'kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle');
      expect(embedder.surfaceType, equals('kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle'));

      // Valid handle should succeed.
      expect(embedder.bindSharedSurface(2588), isTrue);

      // Zero handle should throw InvalidDxgiHandle.
      expect(() => embedder.bindSharedSurface(0), throwsA(isA<InvalidDxgiHandle>()));
    });

    test('Given the application is running on Windows, allocates/validates payload with shared handle and surface type correctly', () {
      const bridge = WindowsDxgiBridge(isWindows: true);

      final payload = {
        'dxgiHandle': '0x0000000000000A1C',
        'width': 1920,
        'height': 1080,
        'surfaceType': 'kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle',
      };

      expect(bridge.validatePayload(payload), isTrue);
    });

    test('validatePayload handles integer dxgiHandle and parses it correctly', () {
      const bridge = WindowsDxgiBridge(isWindows: true);

      final payload = {
        'dxgiHandle': 2588,
        'width': 1920,
        'height': 1080,
        'surfaceType': 'kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle',
      };

      expect(bridge.validatePayload(payload), isTrue);
    });

    test('validatePayload throws InvalidDxgiHandle on invalid or zero handle', () {
      const bridge = WindowsDxgiBridge(isWindows: true);

      // Null handle
      expect(
        () => bridge.validatePayload({
          'width': 1920,
          'height': 1080,
          'surfaceType': 'kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle',
        }),
        throwsA(isA<InvalidDxgiHandle>()),
      );

      // Zero handle string
      expect(
        () => bridge.validatePayload({
          'dxgiHandle': '0x0000000000000000',
          'width': 1920,
          'height': 1080,
          'surfaceType': 'kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle',
        }),
        throwsA(isA<InvalidDxgiHandle>()),
      );

      // Zero handle int
      expect(
        () => bridge.validatePayload({
          'dxgiHandle': 0,
          'width': 1920,
          'height': 1080,
          'surfaceType': 'kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle',
        }),
        throwsA(isA<InvalidDxgiHandle>()),
      );

      // Empty handle string
      expect(
        () => bridge.validatePayload({
          'dxgiHandle': '   ',
          'width': 1920,
          'height': 1080,
          'surfaceType': 'kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle',
        }),
        throwsA(isA<InvalidDxgiHandle>()),
      );
    });

    test('validatePayload throws SurfaceBindingFailure on invalid width or height', () {
      const bridge = WindowsDxgiBridge(isWindows: true);

      expect(
        () => bridge.validatePayload({
          'dxgiHandle': '0x0000000000000A1C',
          'width': 0,
          'height': 1080,
          'surfaceType': 'kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle',
        }),
        throwsA(isA<SurfaceBindingFailure>()),
      );

      expect(
        () => bridge.validatePayload({
          'dxgiHandle': '0x0000000000000A1C',
          'width': 1920,
          'height': -10,
          'surfaceType': 'kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle',
        }),
        throwsA(isA<SurfaceBindingFailure>()),
      );
    });

    test('validatePayload throws InvalidDxgiHandle if surfaceType is not kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle on Windows', () {
      const bridge = WindowsDxgiBridge(isWindows: true);

      final payload = {
        'dxgiHandle': '0x0000000000000A1C',
        'width': 1920,
        'height': 1080,
        'surfaceType': 'invalidSurfaceType',
      };

      expect(() => bridge.validatePayload(payload), throwsA(isA<InvalidDxgiHandle>()));
    });

    test('validatePayload allows other surfaceTypes when not on Windows', () {
      const bridge = WindowsDxgiBridge(isWindows: false);

      final payload = {
        'dxgiHandle': '0x0000000000000A1C',
        'width': 1920,
        'height': 1080,
        'surfaceType': 'invalidSurfaceType',
      };

      expect(bridge.validatePayload(payload), isTrue);
    });
  });
}
