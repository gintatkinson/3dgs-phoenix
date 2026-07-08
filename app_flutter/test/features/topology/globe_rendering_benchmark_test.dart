import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_flutter/features/topology/scene_3d_viewport.dart';
import 'package:app_flutter/domain/cesium_3d/virtual_camera.dart';
import 'package:app_flutter/features/topology/topology_map.dart';

void main() {
  test('Stress test: 10k nodes and 50k links rendering loop', () {
    // 1. Generate 10,000 ground nodes
    final List<TopologyNode> nodes = [];
    final int nodeCount = 10000;
    for (int i = 0; i < nodeCount; i++) {
      // Dense grid of nodes around Japan
      final double lat = 30.0 + (i % 100) * 0.15;
      final double lng = 125.0 + (i ~/ 100) * 0.2;
      nodes.add(TopologyNode(
        id: 'node_$i',
        label: 'Node $i',
        position: TopologyNodePosition(
          dim0: lng,
          dim1: lat,
          dim2: 50.0 + (i % 10) * 5.0,
          timeIndex: 0,
          vector: const [],
        ),
        status: 'Active',
      ));
    }

    // 2. Generate 4 satellite orbital nodes
    for (int i = 1; i <= 4; i++) {
      nodes.add(TopologyNode(
        id: 'sat_$i',
        label: 'Satellite $i',
        position: TopologyNodePosition(
          dim0: 130.0 + i * 5.0,
          dim1: 35.0 + i * 2.0,
          dim2: 1000000.0 + i * 200000.0,
          timeIndex: 0,
          vector: const [],
        ),
        status: 'Active',
      ));
    }

    // 3. Generate 50,000 links
    final List<TopologyLink> links = [];
    for (int i = 0; i < nodeCount; i++) {
      final int satIndex = (i % 4) + 1;
      links.add(TopologyLink(source: 'node_$i', target: 'sat_$satIndex', type: 'depends_on'));
      
      for (int n = 1; n <= 4; n++) {
        final int targetIndex = (i + n) % nodeCount;
        links.add(TopologyLink(source: 'node_$i', target: 'node_$targetIndex', type: 'depends_on'));
      }
    }

    final TopologyData topologyData = TopologyData(
      coordinateMapping: const {
        "x": "position/dim_0",
        "y": "position/dim_1",
        "z": "position/dim_2",
      },
      nodes: nodes,
      links: links,
    );

    // 4. Initialize VirtualCamera
    final camera = VirtualCamera.clamped(
      latitude: 35.0,
      longitude: 135.0,
      altitude: 2000000.0,
      heading: 0.0,
      pitch: -45.0,
      roll: 0.0,
    );

    final painter = Scene3DViewportPainter(
      camera: camera,
      activeStyle: 'dark',
      astronomicalBody: 'Earth',
      elevationActive: true,
      showDevices: true,
      showLinks: true,
      showLabels: false, // Turn off labels for pure rendering benchmark
      showDropLines: true,
      userRotationX: 0.0,
      userTilt: 0.0,
      zoomScale: 1.0,
      topologyData: topologyData,
    );

    // 5. Benchmark frame rendering loop (100 frames)
    final stopwatch = Stopwatch()..start();
    const int frameCount = 100;
    const Size viewportSize = Size(1920, 1080);
    final PictureRecorder recorder = PictureRecorder();
    final Canvas canvas = Canvas(recorder);

    for (int f = 0; f < frameCount; f++) {
      // Update camera slightly to force re-projection of all 10k nodes
      final currentCamera = VirtualCamera.clamped(
        latitude: 35.0,
        longitude: 135.0 + (f * 0.1),
        altitude: 2000000.0,
        heading: f * 0.5,
        pitch: -45.0 - (f * 0.05),
        roll: 0.0,
      );

      final framePainter = Scene3DViewportPainter(
        camera: currentCamera,
        activeStyle: 'dark',
        astronomicalBody: 'Earth',
        elevationActive: true,
        showDevices: true,
        showLinks: true,
        showLabels: false,
        showDropLines: true,
        userRotationX: 0.0,
        userTilt: 0.0,
        zoomScale: 1.0,
        topologyData: topologyData,
      );

      framePainter.paint(canvas, viewportSize);
    }

    stopwatch.stop();
    final double totalElapsedMs = stopwatch.elapsedMilliseconds.toDouble();
    final double avgFrameTimeMs = totalElapsedMs / frameCount;

    print('--- PERFORMANCE BENCHMARK RESULTS ---');
    print('Total nodes: ${nodes.length}');
    print('Total links: ${links.length}');
    print('Total frames rendered: $frameCount');
    print('Total elapsed time: ${totalElapsedMs.toStringAsFixed(2)} ms');
    print('Average frame render time: ${avgFrameTimeMs.toStringAsFixed(2)} ms');
    print('Equivalent frame rate: ${(1000.0 / avgFrameTimeMs).toStringAsFixed(2)} fps');
    print('--------------------------------------');

    expect(avgFrameTimeMs, lessThan(22.0), reason: 'Average frame render time should be under 22.0ms (60fps)');
  });
}
