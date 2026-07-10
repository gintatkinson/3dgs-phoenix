import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_flutter/domain/cesium_3d/renderers/globe_renderer.dart';
import 'package:app_flutter/domain/cesium_3d/renderers/globe_mesh.dart';
import 'package:app_flutter/domain/cesium_3d/renderers/tile_atlas.dart';
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
  // Ensure Flutter binding is initialized for loading shaders.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GlobeRenderer and GlobePainter Tests', () {
    late ui.FragmentShader globeShader;
    late ui.FragmentShader atmosphereShader;
    late ui.Image testImage;

    setUpAll(() async {
      final globeProgram = await ui.FragmentProgram.fromAsset('shaders/globe.frag');
      globeShader = globeProgram.fragmentShader();

      final atmosphereProgram = await ui.FragmentProgram.fromAsset('shaders/atmosphere.frag');
      atmosphereShader = atmosphereProgram.fragmentShader();

      // Create a real ui.Image synchronously for testing image binding.
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 10.0, 10.0),
        ui.Paint()..color = const Color(0xFF00FF00),
      );
      final picture = recorder.endRecording();
      testImage = picture.toImageSync(10, 10);
    });

    test('Successful instantiation and initialization', () {
      final globeMesh = GlobeMesh.generateIcosahedron(subdivisionLevel: 0);
      final tileAtlas = TileAtlas(columns: 2, rows: 2);

      final renderer = GlobeRenderer(
        globeShader: globeShader,
        atmosphereShader: atmosphereShader,
        globeMesh: globeMesh,
        tileAtlas: tileAtlas,
        atlasTexture: testImage,
      );

      expect(renderer.globeShader, same(globeShader));
      expect(renderer.atmosphereShader, same(atmosphereShader));
      expect(renderer.globeMesh, same(globeMesh));
      expect(renderer.tileAtlas, same(tileAtlas));
      expect(renderer.atlasTexture, same(testImage));

      final camera = VirtualCamera.zero;
      final painter = GlobePainter(
        renderer: renderer,
        camera: camera,
        blendAlpha: 0.8,
        atmosphereColor: const Color.fromARGB(255, 100, 150, 200),
        glowPower: 3.0,
      );

      expect(painter.renderer, same(renderer));
      expect(painter.camera, same(camera));
      expect(painter.blendAlpha, equals(0.8));
      expect(painter.atmosphereColor, equals(const Color.fromARGB(255, 100, 150, 200)));
      expect(painter.glowPower, equals(3.0));
    });

    test('Successful painting on MockCanvas using real shaders', () {
      final globeMesh = GlobeMesh.generateIcosahedron(subdivisionLevel: 0);
      final tileAtlas = TileAtlas(columns: 2, rows: 2);

      final renderer = GlobeRenderer(
        globeShader: globeShader,
        atmosphereShader: atmosphereShader,
        globeMesh: globeMesh,
        tileAtlas: tileAtlas,
        atlasTexture: testImage,
      );

      // Setup camera looking at the origin, with large altitude so that the globe is visible/projected
      final camera = VirtualCamera(
        latitude: 0.0,
        longitude: 0.0,
        altitude: 10000000.0, // 10,000 km altitude
        heading: 0.0,
        pitch: -90.0, // pointing down to earth center
        roll: 0.0,
      );

      final painter = GlobePainter(
        renderer: renderer,
        camera: camera,
        blendAlpha: 0.75,
        atmosphereColor: const Color.fromARGB(255, 50, 100, 150),
        glowPower: 2.5,
      );

      final canvas = MockCanvas();
      const viewSize = Size(800.0, 600.0);

      // Invoke paint - should set uniforms and draw both atmosphere and globe vertices.
      expect(() => painter.paint(canvas, viewSize), returnsNormally);

      // Verify draw calls and parameters
      expect(canvas.drawCalls, containsAllInOrder(['drawRect', 'drawVertices']));
      expect(canvas.lastRect, equals(const Rect.fromLTWH(0, 0, 800.0, 600.0)));
      expect(canvas.lastRectPaint?.shader, same(atmosphereShader));
      expect(canvas.lastVertices, isNotNull);
      expect(canvas.lastVerticesPaint?.shader, same(globeShader));
    });
  });
}
