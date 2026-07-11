import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:app_flutter/domain/cesium_3d/renderers/tile_atlas.dart';

// A mock implementation of ui.Image using Fake to track disposal.
class MockUiImage extends Fake implements ui.Image {
  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
  }
}

void main() {
  group('TileAtlas LRU & VRAM Lifecycle Tests', () {
    test('evicted slots call ui.Image.dispose()', () {
      final atlas = TileAtlas(columns: 2, rows: 2); // capacity = 4

      final img0 = MockUiImage();
      final img1 = MockUiImage();
      final img2 = MockUiImage();
      final img3 = MockUiImage();

      // Allocate 4 tiles to fill the atlas capacity.
      atlas.getOrCreateTile('tile_0');
      atlas.getOrCreateTile('tile_1');
      atlas.getOrCreateTile('tile_2');
      atlas.getOrCreateTile('tile_3');

      // Associate mock ui.Images.
      atlas.setImage('tile_0', img0);
      atlas.setImage('tile_1', img1);
      atlas.setImage('tile_2', img2);
      atlas.setImage('tile_3', img3);

      // Verify no images are disposed yet.
      expect(img0.disposed, isFalse);
      expect(img1.disposed, isFalse);
      expect(img2.disposed, isFalse);
      expect(img3.disposed, isFalse);

      // Allocate a 5th tile ('tile_4').
      // This should cause the eviction of the least recently used slot ('tile_0').
      atlas.getOrCreateTile('tile_4');

      // Verify that the evicted slot's image is disposed immediately.
      expect(img0.disposed, isTrue);
      expect(img1.disposed, isFalse);
      expect(img2.disposed, isFalse);
      expect(img3.disposed, isFalse);
    });

    test('emergency clear is triggered when allocatedBytes exceeds 512MB', () {
      // 10240 * 10240 * 4 bytes = 419,430,400 bytes (400 MB) per slot.
      final atlas = TileAtlas(
        columns: 2,
        rows: 2,
        slotWidth: 10240,
        slotHeight: 10240,
      );

      final img0 = MockUiImage();
      final img1 = MockUiImage();

      // Allocate first tile. Size = 1. allocatedBytes = 400 MB (<= 512 MB).
      atlas.getOrCreateTile('tile_0');
      atlas.setImage('tile_0', img0);

      expect(atlas.size, equals(1));
      expect(atlas.allocatedBytes, equals(400 * 1024 * 1024));
      expect(img0.disposed, isFalse);

      // Allocate second tile. Size = 2. allocatedBytes = 800 MB (> 512 MB).
      atlas.getOrCreateTile('tile_1');

      // Attempting to set the image for 'tile_1' should trigger the emergency clear.
      // This throws StateError because clear() removes the slot allocation.
      expect(
        () => atlas.setImage('tile_1', img1),
        throwsStateError,
      );

      // Verify that the atlas is cleared and the images are disposed.
      expect(atlas.size, equals(0));
      expect(atlas.allocatedBytes, equals(0));
      expect(img0.disposed, isTrue);
      expect(img1.disposed, isTrue);
    });
  });
}
