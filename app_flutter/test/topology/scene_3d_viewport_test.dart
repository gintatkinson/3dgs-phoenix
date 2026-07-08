import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_flutter/domain/cesium_3d/virtual_camera.dart';
import 'package:app_flutter/features/topology/scene_3d_viewport.dart';

void main() {
  group('Scene3DViewportPainter horizon culling regression tests', () {
    const double R = 6378137.0;

    test('Camera looking down from 20,000 km altitude', () {
      final camera = VirtualCamera.clamped(
        latitude: 0.0,
        longitude: 0.0,
        altitude: 20000000.0, // 20,000 km
        heading: 0,
        pitch: -90, // looking straight down
        roll: 0,
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
        userRotationX: 0.0,
        userTilt: 0.0,
        zoomScale: 1.0,
      );

      // Node A: on the near surface directly under the camera
      final resultA = painter.project(
        0.0, // 0 radians lat
        0.0, // 0 radians lng
        R,   // surface of the Earth
        const Offset(400, 300),
        0.0,
        0.0,
        const Size(800, 600),
      );

      // Node directly under camera on the near side should NOT be culled
      expect(resultA.z, greaterThan(0.0));

      // Node B: on the opposite side of the Earth
      final resultB = painter.project(
        0.0,
        math.pi, // opposite longitude
        R,       // surface
        const Offset(400, 300),
        0.0,
        0.0,
        const Size(800, 600),
      );

      // Node on the opposite side must be culled
      expect(resultB.z, equals(-1.0));
    });

    test('Camera looking up from 1000 km altitude towards a high-altitude satellite', () {
      final camera = VirtualCamera.clamped(
        latitude: 0.0,
        longitude: 0.0,
        altitude: 1000000.0, // 1000 km
        heading: 0,
        pitch: 90, // looking straight up
        roll: 0,
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
        userRotationX: 0.0,
        userTilt: 0.0,
        zoomScale: 1.0,
      );

      // Node C: high-altitude satellite directly overhead at 20,000 km altitude
      // distance from camera is 19,000 km (which exceeds the camera's horizon distance limit)
      final resultC = painter.project(
        0.0,
        0.0,
        R + 20000000.0, // 20,000 km alt
        const Offset(400, 300),
        0.0,
        0.0,
        const Size(800, 600),
      );

      // Directly overhead high-altitude satellite should NOT be culled by the new logic
      expect(resultC.z, greaterThan(0.0));
    });

    test('Horizon clamping centers on projected Earth center under tilted camera', () {
      final camera = VirtualCamera.clamped(
        latitude: 0.0,
        longitude: 0.0,
        altitude: 10000000.0, // 10,000 km altitude
        heading: 0,
        pitch: -45, // Tilted camera (not looking straight down)
        roll: 0,
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
        userRotationX: 0.0,
        userTilt: 0.0,
        zoomScale: 1.0,
      );

      const Size viewportSize = Size(800, 600);
      const Offset viewportCenter = Offset(360.0, 300.0); // 800 * 0.45, 600 * 0.5

      final earthCenterProj = painter.project(
        0.0,
        0.0,
        0.0, // height = 0 is center
        viewportCenter,
        0.0,
        0.0,
        viewportSize,
      );
      final Offset projectedCenter = earthCenterProj.offset;

      final culledPointProj = painter.project(
        0.0,
        math.pi, // opposite longitude
        R,       // surface
        viewportCenter,
        0.0,
        0.0,
        viewportSize,
      );

      expect(culledPointProj.z, equals(-1.0));

      final double dx = culledPointProj.offset.dx - projectedCenter.dx;
      final double dy = culledPointProj.offset.dy - projectedCenter.dy;
      final double distanceToProjectedCenter = math.sqrt(dx * dx + dy * dy);

      final double cRad = R + camera.altitude;
      final double F = viewportSize.shortestSide * 1.2;
      final double radDiff = cRad * cRad - R * R;
      final double expectedProjectedRadius = R * F / math.sqrt(radDiff <= 0.0 ? 1.0 : radDiff);

      // Under a tilted camera (pitch: -45), the horizon circle is projected as an ellipse.
      // The clamped point is shifted along the camera's local east axis, so its projected distance
      // is scaled by 1 / cos(alpha) where alpha = 45 degrees.
      final double expectedProjectedRadiusTilted = expectedProjectedRadius / math.cos(math.pi / 4);

      expect(distanceToProjectedCenter, closeTo(expectedProjectedRadiusTilted, 1e-4));
    });

    test('Near-plane coordinates do not explode for vertices behind camera', () {
      final camera = VirtualCamera.clamped(
        latitude: 35.0,
        longitude: 135.0,
        altitude: 200000.0, // 200 km altitude
        heading: 0,
        pitch: -23, // tilted view
        roll: 0,
      );

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

      const Size viewportSize = Size(800, 600);
      const Offset viewportCenter = Offset(400.0, 300.0);

      // Project a point that is behind the camera plane
      final proj = painter.project(
        0.5, // 30 degrees latitude
        2.3, // 131 degrees longitude
        6378137.0, // surface
        viewportCenter,
        0.0,
        0.0,
        viewportSize,
      );

      // Check that the projected coordinates are safe and do not explode to huge values (e.g. > 100k pixels)
      expect(proj.offset.dx.abs(), lessThan(5000.0));
      expect(proj.offset.dy.abs(), lessThan(5000.0));
    });
  });

  group('Feature 02: 3D Terrain Elevation and Node Altitude', () {
    test('getElevation returns correct heights at Mount Fuji and Alps only when active', () {
      final camera = VirtualCamera.clamped(latitude: 35.0, longitude: 138.0, altitude: 2000000.0, heading: 0, pitch: -90, roll: 0);
      final painterActive = Scene3DViewportPainter(
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
      final painterInactive = Scene3DViewportPainter(
        camera: camera,
        activeStyle: 'dark',
        astronomicalBody: 'Earth',
        elevationActive: false,
        showDevices: true,
        showLinks: true,
        showLabels: true,
        showDropLines: true,
        userRotationX: 0.0,
        userTilt: 0.0,
        zoomScale: 1.0,
      );

      // Mount Fuji Peak: 35.3606, 138.7274
      expect(painterActive.getElevation(35.3606, 138.7274), closeTo(3776.0, 1.0));
      expect(painterInactive.getElevation(35.3606, 138.7274), 0.0);

      // Outside range
      expect(painterActive.getElevation(0.0, 0.0), 0.0);
    });
  });
}
