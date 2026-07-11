import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:app_flutter/domain/cesium_3d/culler.dart';

void main() {
  group('Culler Tests', () {
    const double R = Culler.earthRadius;
    final fovRad = 45.0 * math.pi / 180.0; // 45 degrees FOV

    test('Object directly in front of camera and above horizon is visible', () {
      final cameraPos = Vector3(0.0, 0.0, 10000000.0); // 10,000 km (above North Pole)
      final cameraDir = Vector3(0.0, 0.0, -1.0); // Looking straight down at Earth
      final targetCenter = Vector3(0.0, 0.0, R); // At the North Pole surface
      const radius = 100.0;

      final visible = Culler.isVisible(targetCenter, radius, cameraPos, cameraDir, fovRad);
      expect(visible, isTrue);
    });

    test('Object behind camera is not visible', () {
      final cameraPos = Vector3(0.0, 0.0, 10000000.0);
      final cameraDir = Vector3(0.0, 0.0, 1.0); // Looking away from Earth
      final targetCenter = Vector3(0.0, 0.0, R);
      const radius = 100.0;

      final visible = Culler.isVisible(targetCenter, radius, cameraPos, cameraDir, fovRad);
      expect(visible, isFalse);
    });

    test('Object outside frustum FOV is not visible', () {
      final cameraPos = Vector3(0.0, 0.0, 10000000.0);
      final cameraDir = Vector3(0.0, 0.0, -1.0);
      // Place target far to the side (x = 5,000 km) so it lies outside the 45-deg FOV frustum
      final targetCenter = Vector3(5000000.0, 0.0, R);
      const radius = 100.0;

      final visible = Culler.isVisible(targetCenter, radius, cameraPos, cameraDir, fovRad);
      expect(visible, isFalse);
    });

    test('Object on the opposite side of Earth is blocked by horizon', () {
      final cameraPos = Vector3(0.0, 0.0, 10000000.0); // Above North Pole
      final cameraDir = Vector3(0.0, 0.0, -1.0);
      final targetCenter = Vector3(0.0, 0.0, -R); // South Pole surface (blocked by Earth)
      const radius = 100.0;

      final visible = Culler.isVisible(targetCenter, radius, cameraPos, cameraDir, fovRad);
      expect(visible, isFalse);
    });

    test('Camera inside Earth does not horizon-cull objects', () {
      final cameraPos = Vector3(0.0, 0.0, R - 1000.0); // Slightly below crust
      final cameraDir = Vector3(0.0, 0.0, 1.0); // Looking up
      final targetCenter = Vector3(0.0, 0.0, R + 1000.0); // Above surface
      const radius = 100.0;

      final visible = Culler.isVisible(targetCenter, radius, cameraPos, cameraDir, fovRad);
      // Should not be horizon-culled since camera is inside/below Earth radius threshold check
      expect(visible, isTrue);
    });

    test('Huge object intersecting frustum is visible even if center is outside FOV', () {
      final cameraPos = Vector3(0.0, 0.0, 10000000.0);
      final cameraDir = Vector3(0.0, 0.0, -1.0);
      final targetCenter = Vector3(5000000.0, 0.0, R);
      const radius = 4000000.0; // Giant radius that extends into the FOV

      final visible = Culler.isVisible(targetCenter, radius, cameraPos, cameraDir, fovRad);
      expect(visible, isTrue);
    });

    group('isLinkOccluded tests', () {
      test('Segment entirely above Earth on one side is not occluded', () {
        final nodeA = Vector3(0.0, 0.0, R + 1000.0);
        final nodeB = Vector3(10000.0, 0.0, R + 1000.0);
        expect(Culler.isLinkOccluded(nodeA, nodeB), isFalse);
      });

      test('Segment passing through the Earth is occluded', () {
        final nodeA = Vector3(0.0, 0.0, R + 1000.0);
        final nodeB = Vector3(0.0, 0.0, -R - 1000.0); // passes through core
        expect(Culler.isLinkOccluded(nodeA, nodeB), isTrue);
      });

      test('Segment tangent to Earth surface but passing below it is occluded', () {
        // Points on opposite sides of a chord that passes closer to center than R
        final nodeA = Vector3(-R, 0.0, 100.0);
        final nodeB = Vector3(R, 0.0, 100.0);
        // The midpoint is (0, 0, 100) which has magnitude 100 < R, so it passes through Earth
        expect(Culler.isLinkOccluded(nodeA, nodeB), isTrue);
      });
    });
  });
}

