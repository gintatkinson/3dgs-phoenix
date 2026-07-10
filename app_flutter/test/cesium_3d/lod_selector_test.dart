import 'package:flutter_test/flutter_test.dart';
import 'package:app_flutter/domain/cesium_3d/lod_selector.dart';

void main() {
  group('LodSelector Tests', () {
    test('Default threshold is 16.0', () {
      const selector = LodSelector();
      expect(selector.threshold, equals(16.0));
    });

    test('Custom threshold is respected', () {
      const selector = LodSelector(threshold: 32.0);
      expect(selector.threshold, equals(32.0));
    });

    test('Zoom 0 tile splits at close camera alt but does not split at very far camera alt', () {
      const selector = LodSelector(threshold: 16.0);
      // Zoom 0 tile width = 40075016.68
      // cameraAlt = 10,000,000 (10k km), viewportWidth = 1000
      // sse = (40075016.68 / 10000000) * 1000 = 4007.5 > 16.0 (should split)
      expect(selector.shouldSplit(0, 0, 0, 10000000.0, 1000.0), isTrue);

      // cameraAlt = 10,000,000,000 (10m km), viewportWidth = 1000
      // sse = (40075016.68 / 10000000000) * 1000 = 4.0075 < 16.0 (should NOT split)
      expect(selector.shouldSplit(0, 0, 0, 10000000000.0, 1000.0), isFalse);
    });

    test('Zoom 15 tile splits at 10km alt but does not split at 100km alt', () {
      const selector = LodSelector(threshold: 16.0);
      // Zoom 15 tile width = 40075016.68 / 32768 = 1222.99
      
      // cameraAlt = 10,000, viewportWidth = 1000
      // sse = (1222.99 / 10000) * 1000 = 122.299 > 16.0 (should split)
      expect(selector.shouldSplit(15, 0, 0, 10000.0, 1000.0), isTrue);

      // cameraAlt = 100,000, viewportWidth = 1000
      // sse = (1222.99 / 100000) * 1000 = 12.2299 < 16.0 (should NOT split)
      expect(selector.shouldSplit(15, 0, 0, 100000.0, 1000.0), isFalse);
    });

    test('Camera altitude at or below ground level always forces a split', () {
      const selector = LodSelector();
      expect(selector.shouldSplit(10, 0, 0, 0.0, 1000.0), isTrue);
      expect(selector.shouldSplit(10, 0, 0, -50.0, 1000.0), isTrue);
    });
  });
}
