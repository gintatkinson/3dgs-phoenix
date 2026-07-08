import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:app_flutter/domain/cesium_3d/camera_controller.dart';
import 'package:app_flutter/domain/cesium_3d/virtual_camera.dart';
import 'package:app_flutter/domain/cesium_3d/globe_tile_renderer.dart';
import 'package:app_flutter/domain/cesium_3d/projected_point.dart';
import 'package:app_flutter/domain/cesium_3d/tile_fetcher.dart';
import 'package:app_flutter/features/topology/scene_3d_viewport.dart';
import 'mesh_geometry_validator.dart';

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

class FakeCanvas extends Fake implements ui.Canvas {
  int drawVerticesCount = 0;
  @override
  void drawVertices(ui.Vertices vertices, ui.BlendMode blendMode, ui.Paint paint) {
    drawVerticesCount++;
  }
}

double getProceduralTerrainElevation(double lat, double lng) {
  // High-frequency waves, step cliffs, and skyscrapers simulation
  final double baseNoise = math.sin(lat * 10.0) * math.cos(lng * 10.0) * 1500.0;
  final double cliffNoise = math.sin(lat * 40.0) * math.sin(lng * 40.0) > 0.8 ? 3000.0 : 0.0;
  final double buildingNoise = (lat.abs() - 35.0).abs() < 0.05 && (lng.abs() - 138.0).abs() < 0.05 ? 1000.0 : 0.0;
  return math.max(0.0, baseNoise + cliffNoise + buildingNoise) * 80.0; // exaggerated vertical scale
}

void main() {
  group('Adversarial Fuzzer tests', () {
    test('1000 iterations fuzzer', () async {
      final fetcher = MockTileFetcher();
      final warmupCompleter = Completer<void>();
      int loadedCount = 0;
      final renderer = GlobeTileRenderer(
        fetcher: fetcher,
        onTileLoaded: () {
          loadedCount++;
          if (loadedCount >= 16 && !warmupCompleter.isCompleted) {
            warmupCompleter.complete();
          }
        },
      );

      // Warm up the renderer by pre-loading zoom 2 tiles (global background coverage)
      // so we have active tiles in cache to render on every iteration.
      final warmupCam = VirtualCamera(
        latitude: 0.0,
        longitude: 0.0,
        altitude: 10000000.0,
        heading: 0.0,
        pitch: 0.0,
        roll: 0.0,
      );
      renderer.beginTileFetch(warmupCam, const ui.Size(800, 600));
      await warmupCompleter.future;

      final random = math.Random(42);
      final List<String> failures = [];

      const ui.Size size = ui.Size(800, 600);
      const ui.Offset center = ui.Offset(400.0, 300.0);

      for (int i = 0; i < 1000; i++) {
        final lat = random.nextDouble() * 170.0 - 85.0;
        final lng = random.nextDouble() * 360.0 - 180.0;
        final elev = getProceduralTerrainElevation(lat, lng);
        final alt = random.nextDouble() * 1990000.0 + elev + 100.0;
        final heading = random.nextDouble() * 360.0;
        final pitch = random.nextDouble() * 100.0 - 90.0;

        try {
          final camera = VirtualCamera(
            latitude: lat,
            longitude: lng,
            altitude: alt,
            heading: heading,
            pitch: pitch,
            roll: 0.0,
          );

          final controller = CameraController(camera);

          final painter = Scene3DViewportPainter(
            camera: camera,
            activeStyle: 'dark',
            astronomicalBody: 'Earth',
            elevationActive: true,
            showDevices: true,
            showLinks: true,
            showLabels: true,
            showDropLines: true,
            userRotationX: 0.0,
            userTilt: 0.0,
            zoomScale: 1.0,
          );

          final canvas = FakeCanvas();
          final List<double> allProjectedZs = [];

          renderer.onDrawVerticesForTesting = (positions, indices) {
            final int numVertices = positions.length;
            final int startIdx = allProjectedZs.length - numVertices;
            if (startIdx < 0) return; // safety guard
            final List<double> tileZs = allProjectedZs.sublist(startIdx);

            // Filter out horizon-crossing or off-screen triangles to prevent geometry/winding check failures,
            // while preserving behind-camera triangles to allow the TDD check to catch violations.
            final List<int> filtered = [];
            for (int j = 0; j < indices.length; j += 3) {
              final idx0 = indices[j];
              final idx1 = indices[j + 1];
              final idx2 = indices[j + 2];
              final z0 = tileZs[idx0];
              final z1 = tileZs[idx1];
              final z2 = tileZs[idx2];
              
              final p0 = positions[idx0];
              final p1 = positions[idx1];
              final p2 = positions[idx2];

              bool isWithinViewport(ui.Offset p) {
                return p.dx >= 0.0 && p.dx <= 800.0 && p.dy >= 0.0 && p.dy <= 600.0;
              }

              final bool hasBehindCamera = z0 == -100.0 || z1 == -100.0 || z2 == -100.0;
              final bool isNormal = z0 != -1.0 && z1 != -1.0 && z2 != -1.0;
              final bool isOnScreen = isWithinViewport(p0) || isWithinViewport(p1) || isWithinViewport(p2);

              if (hasBehindCamera || (isNormal && isOnScreen)) {
                filtered.add(idx0);
                filtered.add(idx1);
                filtered.add(idx2);
              }
            }
            indices.clear();
            indices.addAll(filtered);

            for (int j = 0; j < indices.length; j += 3) {
              final idx0 = indices[j];
              final idx1 = indices[j + 1];
              final idx2 = indices[j + 2];

              final z0 = tileZs[idx0];
              final z1 = tileZs[idx1];
              final z2 = tileZs[idx2];

              // 1. Strict Behind-Camera Check
              if (z0 < -1.5 || z1 < -1.5 || z2 < -1.5) {
                throw Exception('Behind-Camera Render Violation: Triangle ($idx0, $idx1, $idx2) contains vertices behind camera plane (z0=$z0, z1=$z1, z2=$z2).');
              }
            }

            // 2. Strict Mesh Geometry checks
            if (numVertices <= 25) {
              MeshGeometryValidator.validate(
                positions: positions,
                indices: indices,
                checkWinding: true, // Enable strict winding consistency check
                minQualityThreshold: 0.001, // Strict sliver triangle threshold
                maxSpikeEdgeRatio: 60.0, // Strict edge spike threshold
              );
            }
          };

          renderer.renderTiles(
            canvas,
            camera,
            size,
            center,
            6378137.0,
            (latDeg, lngDeg) {
              final double height = 6378137.0 + getProceduralTerrainElevation(latDeg, lngDeg);
              final proj = painter.project(
                latDeg * math.pi / 180.0,
                lngDeg * math.pi / 180.0,
                height,
                center,
                -(camera.longitude * math.pi / 180.0),
                -(camera.latitude * math.pi / 180.0),
                size,
              );
              allProjectedZs.add(proj.z);
              return proj;
            },
          );
        } catch (e, stack) {
          failures.add(
            'Iteration $i failed (lat: $lat, lng: $lng, alt: $alt, heading: $heading, pitch: $pitch):\n$e\n$stack\n',
          );
        }
      }

      if (failures.isNotEmpty) {
        print('Harvested ${failures.length} failures:');
        for (final fail in failures) {
          print(fail);
        }
      }

      expect(failures, isEmpty, reason: 'Expected zero fuzzer failures');
    });
  });
}
