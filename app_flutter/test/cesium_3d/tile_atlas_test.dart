import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:app_flutter/domain/cesium_3d/renderers/tile_atlas.dart';

class MockImage {
  bool disposed = false;
  void dispose() {
    disposed = true;
  }
}

void main() {
  group('TileAtlas Tests', () {
    test('Basic properties and initialization', () {
      final atlas = TileAtlas(columns: 4, rows: 4, slotWidth: 128, slotHeight: 128);
      expect(atlas.columns, equals(4));
      expect(atlas.rows, equals(4));
      expect(atlas.slotWidth, equals(128));
      expect(atlas.slotHeight, equals(128));
      expect(atlas.capacity, equals(16));
      expect(atlas.size, equals(0));
    });

    test('Basic insertion and mapping to slots', () {
      final atlas = TileAtlas(columns: 2, rows: 2);
      expect(atlas.contains('tile_1'), isFalse);

      final result1 = atlas.getOrCreateTile('tile_1');
      expect(atlas.contains('tile_1'), isTrue);
      expect(atlas.size, equals(1));
      expect(result1.slotIndex, isNotNull);
      expect(atlas.getSlotIndex('tile_1'), equals(result1.slotIndex));

      final result2 = atlas.getOrCreateTile('tile_2');
      expect(result2.slotIndex, isNot(equals(result1.slotIndex)));
      expect(atlas.size, equals(2));
    });

    test('Accurate calculation of UV offset/scale', () {
      final atlas = TileAtlas(columns: 4, rows: 2);

      // Total slots = 8.
      // Column width (UV scale x) = 1 / 4 = 0.25
      // Row height (UV scale y) = 1 / 2 = 0.5

      // Slot 0 (col=0, row=0): index = 0
      final res0 = atlas.getOrCreateTile('tile_0');
      expect(res0.slotIndex, equals(0));
      expect(res0.offset, equals(const ui.Offset(0.0, 0.0)));
      expect(res0.scale, equals(const ui.Size(0.25, 0.5)));

      // Slot 1 (col=1, row=0): index = 1
      final res1 = atlas.getOrCreateTile('tile_1');
      expect(res1.slotIndex, equals(1));
      expect(res1.offset, equals(const ui.Offset(0.25, 0.0)));
      expect(res1.scale, equals(const ui.Size(0.25, 0.5)));

      // Slot 4 (col=0, row=1): index = 4
      // Note: _freeSlots are filled from capacity - 1 down to 0,
      // so when we removeLast(), we get indices in ascending order (0, 1, 2, 3, 4, 5, 6, 7).
      atlas.getOrCreateTile('tile_2'); // index = 2
      atlas.getOrCreateTile('tile_3'); // index = 3
      final res4 = atlas.getOrCreateTile('tile_4'); // index = 4
      expect(res4.slotIndex, equals(4));
      expect(res4.offset, equals(const ui.Offset(0.0, 0.5)));
      expect(res4.scale, equals(const ui.Size(0.25, 0.5)));

      // Slot 7 (col=3, row=1): index = 7
      atlas.getOrCreateTile('tile_5'); // index = 5
      atlas.getOrCreateTile('tile_6'); // index = 6
      final res7 = atlas.getOrCreateTile('tile_7'); // index = 7
      expect(res7.slotIndex, equals(7));
      expect(res7.offset, equals(const ui.Offset(0.75, 0.5)));
      expect(res7.scale, equals(const ui.Size(0.25, 0.5)));
    });

    test('Correct LRU eviction behavior when the atlas is full', () {
      final atlas = TileAtlas(columns: 2, rows: 2); // capacity = 4

      // Insert 4 tiles to fill the atlas.
      // Expected allocation order: slot 0, 1, 2, 3
      final r0 = atlas.getOrCreateTile('tile_0');
      final r1 = atlas.getOrCreateTile('tile_1');
      final r2 = atlas.getOrCreateTile('tile_2');
      final r3 = atlas.getOrCreateTile('tile_3');

      expect(atlas.size, equals(4));
      expect(r0.slotIndex, equals(0));
      expect(r1.slotIndex, equals(1));
      expect(r2.slotIndex, equals(2));
      expect(r3.slotIndex, equals(3));

      // Access 'tile_0' again, moving it to MRU (most recently used).
      // LRU order: tile_1, tile_2, tile_3, tile_0
      final r0Access = atlas.getOrCreateTile('tile_0');
      expect(r0Access.slotIndex, equals(0));

      // Now insert a 5th tile ('tile_4').
      // It should cause eviction of 'tile_1' (the LRU tile).
      final r4 = atlas.getOrCreateTile('tile_4');
      expect(r4.slotIndex, equals(1)); // 'tile_4' gets slot 1 (previously 'tile_1')

      expect(atlas.contains('tile_1'), isFalse);
      expect(atlas.contains('tile_0'), isTrue);
      expect(atlas.contains('tile_2'), isTrue);
      expect(atlas.contains('tile_3'), isTrue);
      expect(atlas.contains('tile_4'), isTrue);
      expect(atlas.size, equals(4));

      // Access 'tile_2' to make it MRU.
      // LRU order now: tile_3, tile_0, tile_4, tile_2
      atlas.getOrCreateTile('tile_2');

      // Insert 'tile_5'. It should evict 'tile_3'.
      final r5 = atlas.getOrCreateTile('tile_5');
      expect(r5.slotIndex, equals(3)); // gets slot 3
      expect(atlas.contains('tile_3'), isFalse);
      expect(atlas.contains('tile_5'), isTrue);
    });

    test('Storing and clearing mock images in slots', () {
      final atlas = TileAtlas(columns: 2, rows: 2);
      final img0 = MockImage();
      final img1 = MockImage();

      atlas.getOrCreateTile('tile_0');
      atlas.getOrCreateTile('tile_1');

      atlas.setImage('tile_0', img0);
      atlas.setImage('tile_1', img1);

      expect(atlas.getImageForTile('tile_0'), same(img0));
      expect(atlas.getImageForTile('tile_1'), same(img1));

      // Evict tile_0 to verify image disposal.
      atlas.getOrCreateTile('tile_2'); // capacity = 4, so no eviction yet.
      atlas.getOrCreateTile('tile_3'); // capacity = 4, filled now.

      // Now evict. LRU order: tile_0, tile_1, tile_2, tile_3.
      // Next insert should evict tile_0.
      atlas.getOrCreateTile('tile_4'); // evicts tile_0

      expect(img0.disposed, isTrue);
      expect(img1.disposed, isFalse);

      // Verify clear disposes of remaining images.
      atlas.clear();
      expect(img1.disposed, isTrue);
      expect(atlas.size, equals(0));
    });

    test('Replacing an image in setImage disposes the old one', () {
      final atlas = TileAtlas(columns: 2, rows: 2);
      atlas.getOrCreateTile('tile_0');

      final imgOld = MockImage();
      final imgNew = MockImage();

      atlas.setImage('tile_0', imgOld);
      atlas.setImage('tile_0', imgNew);

      expect(imgOld.disposed, isTrue);
      expect(imgNew.disposed, isFalse);
      expect(atlas.getImageForTile('tile_0'), same(imgNew));

      // Setting the same image should not dispose it.
      atlas.setImage('tile_0', imgNew);
      expect(imgNew.disposed, isFalse);
    });

    test('Throws StateError if setting image for non-allocated tile', () {
      final atlas = TileAtlas(columns: 2, rows: 2);
      expect(
        () => atlas.setImage('tile_non_existent', MockImage()),
        throwsStateError,
      );
    });

    test('Throws ArgumentError if columns/rows are zero or negative', () {
      expect(() => TileAtlas(columns: 0, rows: 2), throwsArgumentError);
      expect(() => TileAtlas(columns: 2, rows: -1), throwsArgumentError);
    });
  });
}
