import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app_flutter/domain/cesium_3d/globe_tile_renderer.dart';
import 'package:app_flutter/domain/cesium_3d/projected_point.dart';
import 'package:app_flutter/domain/cesium_3d/tile_fetcher.dart';
import 'package:app_flutter/domain/cesium_3d/virtual_camera.dart';
import 'package:app_flutter/features/topology/scene_3d_viewport.dart';
import 'package:app_flutter/features/topology/topology_map.dart';
import 'package:flutter_test/flutter_test.dart';

class MockTileFetcher extends TileFetcher {
  @override
  bool isEnabled() => true;

  @override
  Future<Uint8List?> fetchTile(
      ImageryProvider provider, int z, int x, int y) async {
    return base64Decode(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==");
  }
}

class CountingTileFetcher extends TileFetcher {
  final Set<String> uniqueKeysRequested = {};
  final Map<String, int> networkFetchCounts = {};
  int totalNetworkFetches = 0;
  final Map<String, Uint8List> cache = {};
  final int cacheCapacity;

  CountingTileFetcher({this.cacheCapacity = 128});

  @override
  bool isEnabled() => true;

  void resetCounts() {
    networkFetchCounts.clear();
    totalNetworkFetches = 0;
    uniqueKeysRequested.clear();
  }

  @override
  Future<Uint8List?> fetchTile(
      ImageryProvider provider, int z, int x, int y) async {
    final key = '$z/$x/$y';
    uniqueKeysRequested.add(key);

    if (cache.containsKey(key)) {
      return cache[key];
    }

    networkFetchCounts[key] = (networkFetchCounts[key] ?? 0) + 1;
    totalNetworkFetches++;

    final data = base64Decode(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==");

    if (cache.length >= cacheCapacity) {
      cache.remove(cache.keys.first);
    }
    cache[key] = data;

    return data;
  }
}

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
      // Verify that the high-resolution (zoom 8) search radius is clamped to a safe maximum of 2.
      final hasEdgeTile = zoom8Tiles.any((t) => (t.x - centerTile.x).abs() > 2);
      expect(hasEdgeTile, isFalse, reason: 'High-res search radius must be capped at 2 to fit cache budget');
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

    test('Scenario 4 - Polar cap clamping', () async {
      final fetcher = MockTileFetcher();
      int loadedCount = 0;
      final completer = Completer<void>();

      final renderer = GlobeTileRenderer(
        fetcher: fetcher,
        onTileLoaded: () {
          loadedCount++;
          if (loadedCount >= 16 && !completer.isCompleted) {
            completer.complete();
          }
        },
      );

      final camera = VirtualCamera(
        latitude: 0.0,
        longitude: 0.0,
        altitude: 10000000.0,
        heading: 0.0,
        pitch: 0.0,
        roll: 0.0,
      );

      // Trigger tile fetch for zoom 2 tiles (includes 2/0/0 and 2/0/3)
      renderer.beginTileFetch(camera, const ui.Size(800, 600));
      await completer.future;

      // Now call renderTiles and capture the latitudes passed to projectFn
      final latitudes = <double>[];
      final canvas = ui.Canvas(ui.PictureRecorder());

      renderer.renderTiles(
        canvas,
        camera,
        const ui.Size(800, 600),
        ui.Offset.zero,
        1000.0,
        (lat, lng) {
          latitudes.add(lat);
          return ProjectedPoint(ui.Offset.zero, 1.0);
        },
      );

      // Helper to compute unclamped latitude at zoom 2, y=0 and y=4
      double computeUnclampedLat(double y, int z) {
        final n = math.pi * (1.0 - 2.0 * y / math.pow(2, z));
        return math.atan((math.exp(n) - math.exp(-n)) / 2.0) * 180.0 / math.pi;
      }
      final unclampedNorth = computeUnclampedLat(0, 2);
      final unclampedSouth = computeUnclampedLat(4, 2);

      // Verify that the captured latitudes contain exactly 90.0 and -90.0,
      // and do NOT contain unclamped boundary latitudes (~85.0511 or ~-85.0511)
      expect(latitudes, contains(90.0));
      expect(latitudes, contains(-90.0));
      expect(latitudes, isNot(contains(unclampedNorth)));
      expect(latitudes, isNot(contains(unclampedSouth)));
    });

    test('Test 4 (Scenario 5 - Cache budget safety)', () {
      final fetcher = TileFetcher()..disable();
      final renderer = GlobeTileRenderer(fetcher: fetcher);
      final size = const ui.Size(800, 600);

      // Test at 500,000m altitude
      final cameraLow = VirtualCamera(
        latitude: 0.0,
        longitude: 0.0,
        altitude: 500000.0,
        heading: 0.0,
        pitch: 0.0,
        roll: 0.0,
      );
      final tilesLow = renderer.visibleTilesForTesting(cameraLow, size);
      expect(tilesLow.length, lessThanOrEqualTo(66),
          reason: 'At 500,000m altitude, tile count should not exceed 66 to fit cache budget');

      // Test at 10,000,000m altitude
      final cameraHigh = VirtualCamera(
        latitude: 0.0,
        longitude: 0.0,
        altitude: 10000000.0,
        heading: 0.0,
        pitch: 0.0,
        roll: 0.0,
      );
      final tilesHigh = renderer.visibleTilesForTesting(cameraHigh, size);
      expect(tilesHigh.length, lessThanOrEqualTo(66),
          reason: 'At 10,000,000m altitude, tile count should not exceed 66 to fit cache budget');
    });

    test('Test 5 (Scenario 5 - Caching stability & thrashing prevention)', () async {
      final fetcher = CountingTileFetcher(cacheCapacity: 128);
      final renderer = GlobeTileRenderer(fetcher: fetcher);
      final size = const ui.Size(800, 600);
      final camera = VirtualCamera(
        latitude: 0.0,
        longitude: 0.0,
        altitude: 500000.0,
        heading: 0.0,
        pitch: 0.0,
        roll: 0.0,
      );

      // Call beginTileFetch repeatedly to let fetches process
      for (int i = 0; i < 30; i++) {
        renderer.beginTileFetch(camera, size);
        await Future.delayed(const Duration(milliseconds: 10));
      }

      // The total number of network fetches must not exceed the number of unique tiles requested.
      expect(fetcher.totalNetworkFetches, equals(fetcher.uniqueKeysRequested.length),
          reason: 'Should not have duplicate network fetches for the same tiles (no thrashing)');

      // Reset counters and verify that subsequent calls result in 0 new network fetches
      fetcher.resetCounts();
      renderer.beginTileFetch(camera, size);
      await Future.delayed(const Duration(milliseconds: 20));

      expect(fetcher.totalNetworkFetches, equals(0),
          reason: 'Subsequent calls for a stationary camera must result in 0 new network fetches');
    });

    test('Test 6 (Scenario 6 - Horizon projection clamping)', () {
      final camera = VirtualCamera(
        latitude: 0.0,
        longitude: 0.0,
        altitude: 500000.0, // 500,000m
        heading: 0.0,
        pitch: -90.0,
        roll: 0.0,
      );

      final painter = Scene3DViewportPainter(
        camera: camera,
        activeStyle: 'dark',
        astronomicalBody: 'Earth',
        elevationActive: false,
        showDevices: true,
        showLinks: true,
        showLabels: true,
        showDropLines: true,
        topologyData: const TopologyData(coordinateMapping: {}, nodes: [], links: []),
        userRotationX: 0.0,
        userTilt: 0.0,
        zoomScale: 1.0,
      );

      const double width = 800.0;
      const double height = 600.0;
      final center = ui.Offset(width * 0.45, height * 0.5);
      final size = const ui.Size(width, height);

      final projectedPoint = painter.project(
        0.0, // lat
        math.pi, // lng (180 degrees)
        6378137.0, // height (Earth surface radius)
        center,
        0.0, // rotationY
        0.0, // tilt
        size,
      );

      // Project the Earth's center (0,0,0) in ECEF under the same settings to find the expected projected center
      final earthCenterProj = painter.project(
        0.0,
        0.0,
        0.0, // height = 0 is center
        center,
        0.0,
        0.0,
        size,
      );
      final Offset projectedCenter = earthCenterProj.offset;

      const double R = 6378137.0;
      final double cRad = R + 500000.0;
      final double F = size.shortestSide * 1.2;
      final double projectedRadius = R * F / math.sqrt(cRad * cRad - R * R);

      final double actualDistance = (projectedPoint.offset - projectedCenter).distance;

      // Assert z is equal to -1.0 (culled status)
      expect(projectedPoint.z, equals(-1.0));

      // Assert distance from projectedCenter is close to projectedRadius (within 1e-4 tolerance)
      expect(actualDistance, closeTo(projectedRadius, 1e-4));
    });

    test('Test 5 (Scenario 6 - Discard triangles crossing behind camera)', () async {
      final fetcher = TileFetcher();
      int loadedCount = 0;
      final completer = Completer<void>();

      final renderer = GlobeTileRenderer(
        fetcher: fetcher,
        onTileLoaded: () {
          loadedCount++;
          if (loadedCount >= 16 && !completer.isCompleted) {
            completer.complete();
          }
        },
      );

      final camera = VirtualCamera(
        latitude: 0.0,
        longitude: 0.0,
        altitude: 10000000.0,
        heading: 0.0,
        pitch: 0.0,
        roll: 0.0,
      );

      renderer.beginTileFetch(camera, const ui.Size(800, 600));
      await completer.future;

      final canvas = FakeCanvas();
      int callCount = 0;

      renderer.renderTiles(
        canvas,
        camera,
        const ui.Size(800, 600),
        ui.Offset.zero,
        1000.0,
        (lat, lng) {
          final pt = ProjectedPoint(ui.Offset.zero, callCount == 0 ? 1.0 : -100.0);
          callCount++;
          return pt;
        },
      );

      // Without the fix, triangles containing visible vertex (index 0) are drawn, so drawVerticesCount > 0.
      // With the fix, all triangles containing behind-camera vertices (z < -1.5) are discarded, so drawVerticesCount == 0.
      expect(canvas.drawVerticesCount, equals(0));
    });
  });
}

class FakeCanvas extends Fake implements ui.Canvas {
  int drawVerticesCount = 0;
  @override
  void drawVertices(ui.Vertices vertices, ui.BlendMode blendMode, ui.Paint paint) {
    drawVerticesCount++;
  }
}
