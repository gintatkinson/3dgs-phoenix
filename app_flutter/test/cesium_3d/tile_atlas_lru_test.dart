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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TileAtlas LRU & VRAM Lifecycle Tests', () {
    testWidgets('evicted slots call ui.Image.dispose()', (WidgetTester tester) async {
      final atlas = TileAtlas(columns: 2, rows: 2); // capacity = 4

      final img0 = await _createRealImage(tester);
      final img1 = await _createRealImage(tester);
      final img2 = await _createRealImage(tester);
      final img3 = await _createRealImage(tester);

      // Allocate 4 tiles to fill the atlas capacity.
      atlas.getOrCreateTile('tile_0');
      atlas.getOrCreateTile('tile_1');
      atlas.getOrCreateTile('tile_2');
      atlas.getOrCreateTile('tile_3');

      // Associate real ui.Images.
      atlas.setImage('tile_0', img0);
      atlas.setImage('tile_1', img1);
      atlas.setImage('tile_2', img2);
      atlas.setImage('tile_3', img3);

      // Verify no images are disposed yet.
      expect(img0.debugDisposed, isFalse);
      expect(img1.debugDisposed, isFalse);
      expect(img2.debugDisposed, isFalse);
      expect(img3.debugDisposed, isFalse);

      // Allocate a 5th tile ('tile_4').
      // This should cause the eviction of the least recently used slot ('tile_0').
      atlas.getOrCreateTile('tile_4');

      // Verify that the evicted slot's image is disposed immediately.
      expect(img0.debugDisposed, isTrue);
      expect(img1.debugDisposed, isFalse);
      expect(img2.debugDisposed, isFalse);
      expect(img3.debugDisposed, isFalse);
    });

    testWidgets('emergency clear is triggered when allocatedBytes exceeds 512MB', (WidgetTester tester) async {
      // 10240 * 10240 * 4 bytes = 419,430,400 bytes (400 MB) per slot.
      final atlas = TileAtlas(
        columns: 2,
        rows: 2,
        slotWidth: 10240,
        slotHeight: 10240,
      );

      final img0 = await _createRealImage(tester);
      final img1 = await _createRealImage(tester);

      // Allocate first tile. Size = 1. allocatedBytes = 400 MB (<= 512 MB).
      atlas.getOrCreateTile('tile_0');
      atlas.setImage('tile_0', img0);

      expect(atlas.size, equals(1));
      expect(atlas.allocatedBytes, equals(400 * 1024 * 1024));
      expect(img0.debugDisposed, isFalse);

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
      expect(img0.debugDisposed, isTrue);
      expect(img1.debugDisposed, isTrue);
    });
  });
}
