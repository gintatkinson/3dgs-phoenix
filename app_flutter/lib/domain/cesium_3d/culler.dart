import 'dart:math' as math;
import 'package:vector_math/vector_math_64.dart';

/// Performs frustum and horizon culling on spatial entities in ECEF coordinates.
class Culler {
  /// Mean Earth radius in meters (ECEF coordinates).
  static const double earthRadius = 6378137.0;

  /// Checks if a bounding sphere (defined by [center] and [radius] in ECEF coordinates)
  /// is visible from [cameraPos] looking along [cameraDir] with field of view [fovRad].
  ///
  /// Performs both:
  /// 1. Frustum culling (checking look angle against half-FOV).
  /// 2. Horizon culling (checking line-of-sight blockage by Earth's curvature).
  static bool isVisible(
    Vector3 center,
    double radius,
    Vector3 cameraPos,
    Vector3 cameraDir,
    double fovRad,
  ) {
    // 1. Frustum Culling
    final Vector3 toCenter = center - cameraPos;
    final double distToCenterProj = toCenter.dot(cameraDir);

    // If the sphere is entirely behind the camera plane, it is not visible.
    if (distToCenterProj < -radius) {
      return false;
    }

    final double distToCenter = toCenter.length;
    if (distToCenter > radius) {
      final double cosAlpha = distToCenterProj / distToCenter;
      final double alpha = math.acos(cosAlpha.clamp(-1.0, 1.0));
      final double beta = math.asin((radius / distToCenter).clamp(-1.0, 1.0));

      // If the angle to the sphere minus its angular radius is greater than half-FOV, it is outside the frustum.
      if (alpha - beta > fovRad / 2.0) {
        return false;
      }
    }

    // 2. Horizon Culling
    final double cameraDist = cameraPos.length;
    if (cameraDist > earthRadius) {
      final double dHorizon = math.sqrt(cameraDist * cameraDist - earthRadius * earthRadius);
      final double targetDist = center.length;
      final double targetRadSq = targetDist * targetDist - earthRadius * earthRadius;
      final double dTargetHorizon = targetRadSq > 0 ? math.sqrt(targetRadSq) : 0.0;

      // If the distance to the tile's nearest point is greater than the sum of the
      // camera's horizon distance and the tile's horizon distance, it is blocked by the Earth.
      if (distToCenter - radius > dHorizon + dTargetHorizon) {
        return false;
      }
    }

    return true;
  }
}
