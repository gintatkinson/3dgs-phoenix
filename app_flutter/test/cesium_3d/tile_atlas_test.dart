import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:app_flutter/domain/cesium_3d/renderers/tile_atlas.dart';

Future<ui.Image> _createRealImage(WidgetTester tester) async {
  return await tester.runAsync(() async {
    return await createTestImage(width: 1, height: 1);
  }) as ui.Image;
}

void main() {
  group('TileAtlas Tests', () {
    testWidgets('Basic properties and initialization', (WidgetTester tester) async {
      final atlas = TileAtlas(columns: 4, rows: 4, slotWidth: 128, slotHeight: 128);
      expect(atlas.columns, equals(4));
      expect(atlas.rows, equals(4));
      expect(atlas.slotWidth, equals(128));
      expect(atlas.slotHeight, equals(128));
      expect(atlas.capacity, equals(16));
      expect(atlas.size, equals(0));
    });

    testWidgets('Basic insertion and mapping to slots', (WidgetTester tester) async {
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

    testWidgets('Accurate calculation of UV offset/scale', (WidgetTester tester) async {
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

    testWidgets('Correct LRU eviction behavior when the atlas is full', (WidgetTester tester) async {
      final atlas = TileAtlas(columns: 2, rows: 2); // capacity = 4

      final r0 = atlas.getOrCreateTile('tile_0');
      final r1 = atlas.getOrCreateTile('tile_1');
      final r2 = atlas.getOrCreateTile('tile_2');
      final r3 = atlas.getOrCreateTile('tile_3');

      expect(atlas.size, equals(4));
      expect(r0.slotIndex, equals(0));
      expect(r1.slotIndex, equals(1));
      expect(r2.slotIndex, equals(2));
      expect(r3.slotIndex, equals(3));

      final r0Access = atlas.getOrCreateTile('tile_0');
      expect(r0Access.slotIndex, equals(0));

      final r4 = atlas.getOrCreateTile('tile_4');
      expect(r4.slotIndex, equals(1));

      expect(atlas.contains('tile_1'), isFalse);
      expect(atlas.contains('tile_0'), isTrue);
      expect(atlas.contains('tile_2'), isTrue);
      expect(atlas.contains('tile_3'), isTrue);
      expect(atlas.contains('tile_4'), isTrue);
      expect(atlas.size, equals(4));

      atlas.getOrCreateTile('tile_2');

      final r5 = atlas.getOrCreateTile('tile_5');
      expect(r5.slotIndex, equals(3));
      expect(atlas.contains('tile_3'), isFalse);
      expect(atlas.contains('tile_5'), isTrue);
    });

    testWidgets('Storing and clearing real images in slots', (WidgetTester tester) async {
      final atlas = TileAtlas(columns: 2, rows: 2);
      final img0 = await _createRealImage(tester);
      final img1 = await _createRealImage(tester);

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

      expect(img0.debugDisposed, isTrue);
      expect(img1.debugDisposed, isFalse);

      // Verify clear disposes of remaining images.
      atlas.clear();
      expect(img1.debugDisposed, isTrue);
      expect(atlas.size, equals(0));
    });

    testWidgets('Replacing an image in setImage disposes the old one', (WidgetTester tester) async {
      final atlas = TileAtlas(columns: 2, rows: 2);
      atlas.getOrCreateTile('tile_0');

      final imgOld = await _createRealImage(tester);
      final imgNew = await _createRealImage(tester);

      atlas.setImage('tile_0', imgOld);
      atlas.setImage('tile_0', imgNew);

      expect(imgOld.debugDisposed, isTrue);
      expect(imgNew.debugDisposed, isFalse);
      expect(atlas.getImageForTile('tile_0'), same(imgNew));

      // Setting the same image should not dispose it.
      atlas.setImage('tile_0', imgNew);
      expect(imgNew.debugDisposed, isFalse);
    });

    testWidgets('Throws StateError if setting image for non-allocated tile', (WidgetTester tester) async {
      final atlas = TileAtlas(columns: 2, rows: 2);
      final img = await _createRealImage(tester);
      expect(
        () => atlas.setImage('tile_non_existent', img),
        throwsStateError,
      );
    });

    testWidgets('Throws ArgumentError if columns/rows are zero or negative', (WidgetTester tester) async {
      expect(() => TileAtlas(columns: 0, rows: 2), throwsArgumentError);
      expect(() => TileAtlas(columns: 2, rows: -1), throwsArgumentError);
    });
  });
}
