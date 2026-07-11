import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_flutter/domain/cesium_3d/renderers/globe_renderer.dart';
import 'package:app_flutter/domain/cesium_3d/renderers/globe_mesh.dart';
import 'package:app_flutter/domain/cesium_3d/renderers/tile_atlas.dart';
import 'package:app_flutter/domain/cesium_3d/virtual_camera.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GlobePainter Height Displacement and Projection Tests', () {
    late ui.FragmentShader globeShader;
    late ui.FragmentShader atmosphereShader;
    late GlobeRenderer renderer;
    late VirtualCamera camera;

    setUpAll(() async {
      final globeProgram = await ui.FragmentProgram.fromAsset('shaders/globe.frag');
      globeShader = globeProgram.fragmentShader();

      final atmosphereProgram = await ui.FragmentProgram.fromAsset('shaders/atmosphere.frag');
      atmosphereShader = atmosphereProgram.fragmentShader();
    });

    setUp(() {
      final globeMesh = GlobeMesh.generateIcosahedron(subdivisionLevel: 0);
      final tileAtlas = TileAtlas(columns: 2, rows: 2);

      renderer = GlobeRenderer(
        globeShader: globeShader,
        atmosphereShader: atmosphereShader,
        globeMesh: globeMesh,
        tileAtlas: tileAtlas,
      );

      // Camera positioned at Lat: 0, Lng: 0, looking directly down to the center.
      camera = VirtualCamera(
        latitude: 0.0,
        longitude: 0.0,
        altitude: 10000000.0, // 10,000 km altitude
        heading: 0.0,
        pitch: -90.0,
        roll: 0.0,
      );
    });

    test('Vertex at (1,0,0) with a height of 1000m projects to screen position corresponding to R_earth + 1000m', () {
      final painter = GlobePainter(
        renderer: renderer,
        camera: camera,
        getElevation: (lat, lng) {
          // If lat and lng are close to 0.0, return 1000m
          if (lat.abs() < 0.1 && lng.abs() < 0.1) {
            return 1000.0;
          }
          return 0.0;
        },
      );

      const size = Size(800.0, 600.0);

      // ECEF coordinates scaled for R_earth = 6378137.0.
      // ECEF vertex (R_earth + 1000.0, 0, 0) corresponds to scaled unit position:
      // vx = 1.0 + 1000.0 / 6378137.0; vy = 0.0; vz = 0.0;
      final double scale = 1.0 + 1000.0 / 6378137.0;

      // Project using direct ECEF coordinate projectVertex (without displacement)
      final expectedOffset = painter.projectVertex(scale, 0.0, 0.0, size);

      // Project using projectVertexWithDisplacement (vertex at (1,0,0) with 1000m displacement)
      final actualOffset = painter.projectVertexWithDisplacement(1.0, 0.0, 0.0, size);

      expect(actualOffset.dx, closeTo(expectedOffset.dx, 1e-6));
      expect(actualOffset.dy, closeTo(expectedOffset.dy, 1e-6));
    });

    test('Invalid height inputs (NaN, Infinity, -Infinity, out-of-bounds) are clamped to 0m displacement', () {
      final heights = [
        double.nan,
        double.infinity,
        -double.infinity,
        15000.0, // above 9000m limit
        -15000.0, // below -12000m limit
      ];

      for (final height in heights) {
        final painter = GlobePainter(
          renderer: renderer,
          camera: camera,
          getElevation: (lat, lng) => height,
        );

        const size = Size(800.0, 600.0);

        // Displaced projection should be identical to the 0m projection (which uses unit vector directly)
        final expectedOffset = painter.projectVertex(1.0, 0.0, 0.0, size);
        final actualOffset = painter.projectVertexWithDisplacement(1.0, 0.0, 0.0, size);

        expect(actualOffset.dx, closeTo(expectedOffset.dx, 1e-6));
        expect(actualOffset.dy, closeTo(expectedOffset.dy, 1e-6));
      }
    });
  });
}
