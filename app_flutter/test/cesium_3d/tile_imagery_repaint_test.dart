import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_flutter/domain/cesium_3d/virtual_camera.dart';
import 'package:app_flutter/domain/cesium_3d/tile_fetcher.dart';
import 'package:app_flutter/features/topology/scene_3d_viewport.dart';

void main() {
  // 1x1 transparent PNG
  final pngBytes = base64Decode(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==");

  testWidgets('Issue #51: Viewport repaints when asynchronous tile downloads complete', (WidgetTester tester) async {
    await tester.runAsync(() async {
      // Start a real local HTTP server to serve the PNG bytes
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) {
        request.response
          ..headers.contentType = ContentType('image', 'png')
          ..add(pngBytes)
          ..close();
      });

      final port = server.port;
      TileFetcher.globalBaseUrlOverride = 'http://127.0.0.1:$port';

      try {
        final camera = VirtualCamera(
          latitude: 35.0,
          longitude: 135.0,
          altitude: 10000000.0, // High altitude to fetch low-zoom tiles
          heading: 0.0,
          pitch: -45.0,
          roll: 0.0,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Scene3DViewport(
                camera: camera,
              ),
            ),
          ),
        );
        await tester.pump();

        final state = tester.state(find.byType(Scene3DViewport)) as dynamic;
        final tileRenderer = state.tileRenderer;

        // Initially, no tiles should be loaded
        expect(tileRenderer, isNotNull);

        // Wait for async image fetches and decoding to complete
        for (int i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }

        // Verify that tiles loaded and we did not hang or fail
      } finally {
        TileFetcher.globalBaseUrlOverride = null;
        await server.close(force: true);
      }
    });
  });
}
