import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_flutter/domain/cesium_3d/renderers/globe_renderer.dart';
import 'package:app_flutter/domain/cesium_3d/renderers/globe_mesh.dart';
import 'package:app_flutter/domain/cesium_3d/renderers/tile_atlas.dart';
import 'package:app_flutter/domain/cesium_3d/tile_processor.dart';
import 'package:app_flutter/domain/cesium_3d/virtual_camera.dart';

// Mock Canvas implementation using Fake
class MockCanvas extends Fake implements Canvas {
  final List<String> drawCalls = [];
  Rect? lastRect;
  Paint? lastRectPaint;
  ui.Vertices? lastVertices;
  Paint? lastVerticesPaint;

  @override
  void drawRect(Rect rect, Paint paint) {
    drawCalls.add('drawRect');
    lastRect = rect;
    lastRectPaint = paint;
  }

  @override
  void drawVertices(ui.Vertices vertices, BlendMode blendMode, Paint paint) {
    drawCalls.add('drawVertices');
    lastVertices = vertices;
    lastVerticesPaint = paint;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Globe Shader Compilation and Uniform Bindings Tests', () {
    late ui.FragmentShader globeShader;
    late ui.FragmentShader atmosphereShader;
    late ui.Image testImage;

    setUpAll(() async {
      // 1. Verify shader compilation by loading the assets
      final globeProgram = await ui.FragmentProgram.fromAsset('shaders/globe.frag');
      globeShader = globeProgram.fragmentShader();

      final atmosphereProgram = await ui.FragmentProgram.fromAsset('shaders/atmosphere.frag');
      atmosphereShader = atmosphereProgram.fragmentShader();

      // Create a test image for tileAtlas
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 10.0, 10.0),
        ui.Paint()..color = const Color(0xFF00FF00),
      );
      final picture = recorder.endRecording();
      testImage = picture.toImageSync(10, 10);
    });

    test('Shader compiles successfully and uniform parameter bindings render correctly', () {
      final globeMesh = GlobeMesh.generateIcosahedron(subdivisionLevel: 0);
      final tileAtlas = TileAtlas(columns: 2, rows: 2);
      final geometryCache = TileGeometryCache();

      // Put a mock tile geometry in the cache, with vertices close to (1, 0, 0)
      // to ensure it falls within the visible horizon of a camera looking from (cRad, 0, 0).
      final mockTileGeometry = TileGeometry(
        positions: Float32List.fromList([
          1.0, 0.0, 0.0,
          0.99, 0.01, 0.0,
          0.99, 0.0, 0.01,
        ]),
        texCoords: Float32List.fromList([0.0, 0.0, 1.0, 0.0, 0.0, 1.0]),
        indices: Uint16List.fromList([0, 1, 2]),
      );
      geometryCache.put('tile_test_1', mockTileGeometry);

      // Allocate slot in atlas and set image
      tileAtlas.getOrCreateTile('tile_test_1');
      tileAtlas.setImage('tile_test_1', testImage);

      final renderer = GlobeRenderer(
        globeShader: globeShader,
        atmosphereShader: atmosphereShader,
        globeMesh: globeMesh,
        tileAtlas: tileAtlas,
        atlasTexture: testImage,
        geometryCache: geometryCache,
      );

      final camera = VirtualCamera(
        latitude: 0.0,
        longitude: 0.0,
        altitude: 10000000.0,
        heading: 0.0,
        pitch: -90.0,
        roll: 0.0,
      );

      final painter = GlobePainter(
        renderer: renderer,
        camera: camera,
        geometryCache: geometryCache,
      );

      final canvas = MockCanvas();
      const viewSize = Size(800.0, 600.0);

      // Invoke paint - this should run and set all uniforms (0 to 8) without throwing exceptions,
      // and perform drawVertices for both the base globe and the tile.
      expect(() => painter.paint(canvas, viewSize), returnsNormally);

      // Verify that drawVertices was called for both base globe and the cached tile
      expect(canvas.drawCalls.where((c) => c == 'drawVertices').length, equals(2));
      expect(canvas.lastVertices, isNotNull);
      expect(canvas.lastVerticesPaint?.shader, same(globeShader));
    });
  });
}
