import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:app_flutter/domain/cesium_3d/globe_tile_renderer.dart';
import 'package:app_flutter/domain/cesium_3d/tile_fetcher.dart';
import 'package:app_flutter/domain/cesium_3d/virtual_camera.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GlobeTileRenderer Scenario 4 BDD Tests', () {
    test('Scenario 4 - visible tile grid: horizon search radius verification at high altitude', () {
      final fetcher = TileFetcher()..disable();
      final renderer = GlobeTileRenderer(fetcher: fetcher);
      final camera = VirtualCamera(
        latitude: 0.0,
        longitude: 0.0,
        altitude: 500000.0, // 500,000m
        heading: 0.0,
        pitch: 0.0,
        roll: 0.0,
      );
      final viewportSize = const ui.Size(800, 600);

      // Verify zoom is 8
      // double alt = 500000.0
      // zoom = round(log(120000000.0 / 500000.0) / ln2) = round(log(240.0) / ln2) = round(7.907) = 8.
      final centerTile = renderer.latLngToTileForTesting(camera.latitude, camera.longitude, 8);
      expect(centerTile.zoom, equals(8));

      final visibleTiles = renderer.visibleTilesForTesting(camera, viewportSize);
      final zoom8Tiles = visibleTiles.where((t) => t.zoom == 8).toList();

      // Check if any returned tile is at the edge (dx >= 15)
      // Horizon angle theta = acos(R / (R + h)) = ~21.9 degrees
      // Zoom is 8, tile width is 1.4 degrees, so required radius = ceil(21.9 / 1.4) = ~16 tiles.
      // Verify that tiles at the edge (dx >= 15) are returned.
      final hasEdgeTile = zoom8Tiles.any((t) => (t.x - centerTile.x).abs() >= 15);
      expect(hasEdgeTile, isTrue, reason: 'Expected horizon search to return tiles at the edge (dx >= 15)');
    });

    test('Scenario 4 - soft culling: partial horizon crossing does not cull triangles', () {
      // 25 depth values (5x5 grid)
      // Make only vertex 0 visible, all others hidden below horizon.
      final zs = List<double>.filled(25, -1.0);
      zs[0] = 10.0; // Visible

      final indices = GlobeTileRenderer.calculateIndicesForTesting(zs);

      // Triangle 1: (0, 1, 5) shares vertex 0 (which is visible).
      // Under soft culling, it should not be culled.
      // Under current implementation, it is culled, resulting in empty indices.
      expect(indices, containsAll([0, 1, 5]),
          reason: 'Expected triangle containing visible vertex 0 not to be culled');
    });
  });
}
