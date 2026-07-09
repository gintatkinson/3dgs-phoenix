import 'package:flutter_test/flutter_test.dart';
import 'package:app_flutter/domain/cesium_3d/native/mac_iosurface_bridge.dart';

void main() {
  group('macOS IOSurface Texture Interop Tests', () {
    test('createIoSurface validates width and height constraints', () {
      const bridge = MacIosurfaceBridge();
      
      // Valid width and height should succeed and return mock pointer value.
      final pointer = bridge.createIoSurface(1920, 1080);
      expect(pointer, equals(140735492982848));

      // Invalid width or height <= 0 should throw IoSurfaceCreationFailed.
      expect(() => bridge.createIoSurface(0, 1080), throwsA(isA<IoSurfaceCreationFailed>()));
      expect(() => bridge.createIoSurface(1920, 0), throwsA(isA<IoSurfaceCreationFailed>()));
      expect(() => bridge.createIoSurface(-1, 1080), throwsA(isA<IoSurfaceCreationFailed>()));
      expect(() => bridge.createIoSurface(1920, -5), throwsA(isA<IoSurfaceCreationFailed>()));
    });

    test('bindMetalTexture validates surface pointer constraints', () {
      const bridge = MacIosurfaceBridge();

      // Valid surfaceRef should succeed.
      expect(bridge.bindMetalTexture(140735492982848), isTrue);

      // Zero surfaceRef should throw IoSurfaceCreationFailed.
      expect(() => bridge.bindMetalTexture(0), throwsA(isA<IoSurfaceCreationFailed>()));
    });

    test('Given macOS Apple Silicon, allocates/validates payload with shared storage mode correctly', () {
      // Force Apple Silicon platform environment
      const bridge = MacIosurfaceBridge(isAppleSilicon: true);

      final payload = {
        'ioSurfaceRef': 140735492982848,
        'width': 1920,
        'height': 1080,
        'mtlStorageMode': 'MTLStorageModeShared',
      };

      expect(bridge.validatePayload(payload), isTrue);
    });

    test('Creating/validating texture with unsupported storage mode on Apple Silicon throws MetalValidationError', () {
      // Force Apple Silicon platform environment
      const bridge = MacIosurfaceBridge(isAppleSilicon: true);

      final payload = {
        'ioSurfaceRef': 140735492982848,
        'width': 1920,
        'height': 1080,
        'mtlStorageMode': 'MTLStorageModePrivate',
      };

      expect(() => bridge.validatePayload(payload), throwsA(isA<MetalValidationError>()));
    });

    test('Validating zero pointer value for ioSurfaceRef throws IoSurfaceCreationFailed', () {
      const bridge = MacIosurfaceBridge();

      final payload = {
        'ioSurfaceRef': 0,
        'width': 1920,
        'height': 1080,
        'mtlStorageMode': 'MTLStorageModeShared',
      };

      expect(() => bridge.validatePayload(payload), throwsA(isA<IoSurfaceCreationFailed>()));
    });

    test('Given non-Apple Silicon, validatePayload allows other storage modes', () {
      // Force non-Apple Silicon platform environment (e.g. Intel macOS or other OS)
      const bridge = MacIosurfaceBridge(isAppleSilicon: false);

      final payloadPrivate = {
        'ioSurfaceRef': 140735492982848,
        'width': 1920,
        'height': 1080,
        'mtlStorageMode': 'MTLStorageModePrivate',
      };

      expect(bridge.validatePayload(payloadPrivate), isTrue);
    });

    test('CvPixelBufferInfo constructor and fields initialization', () {
      const info = CvPixelBufferInfo(storageMode: 2, isIoSurfaceBacked: true);
      expect(info.storageMode, equals(2));
      expect(info.isIoSurfaceBacked, isTrue);

      // Verify configure method does not throw.
      expect(() => info.configure(), returnsNormally);
    });
  });
}
