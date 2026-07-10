import 'dart:math' as math;
import 'dart:typed_data';

/// Represents a 3D globe mesh with positions, texture coordinates, and indices.
class GlobeMesh {
  /// Float32List of vertex positions (x, y, z).
  final Float32List positions;

  /// Float32List of texture coordinates (u, v).
  final Float32List texCoords;

  /// Uint16List of indices defining the triangles.
  final Uint16List indices;

  /// Creates a new [GlobeMesh] instance.
  GlobeMesh({
    required this.positions,
    required this.texCoords,
    required this.indices,
  });

  /// Generates a tessellated icosphere (subdivided icosahedron) on the unit sphere.
  ///
  /// The [subdivisionLevel] controls the density of the mesh:
  /// - Level 5 yields 10,346 vertices and 61,440 indices.
  /// - Level 6 yields 41,162 vertices and 245,760 indices (within Uint16 limits).
  static GlobeMesh generateIcosahedron({int subdivisionLevel = 5}) {
    if (subdivisionLevel < 0) {
      throw ArgumentError('subdivisionLevel must be non-negative');
    }

    // 1. Generate the 12 base vertices of a regular icosahedron using the golden ratio.
    final double t = (1.0 + math.sqrt(5.0)) / 2.0;

    final List<double> basePositions = [
      -1.0, t, 0.0,
      1.0, t, 0.0,
      -1.0, -t, 0.0,
      1.0, -t, 0.0,

      0.0, -1.0, t,
      0.0, 1.0, t,
      0.0, -1.0, -t,
      0.0, 1.0, -t,

      t, 0.0, -1.0,
      t, 0.0, 1.0,
      -t, 0.0, -1.0,
      -t, 0.0, 1.0,
    ];

    // Normalize base vertices to lie precisely on the unit sphere.
    for (int i = 0; i < basePositions.length; i += 3) {
      final double x = basePositions[i];
      final double y = basePositions[i + 1];
      final double z = basePositions[i + 2];
      final double length = math.sqrt(x * x + y * y + z * z);
      basePositions[i] = x / length;
      basePositions[i + 1] = y / length;
      basePositions[i + 2] = z / length;
    }

    // Base 20 faces of the icosahedron.
    List<int> currentIndices = [
      0, 11, 5,
      0, 5, 1,
      0, 1, 7,
      0, 7, 10,
      0, 10, 11,

      1, 5, 9,
      5, 11, 4,
      11, 10, 2,
      10, 7, 6,
      7, 1, 8,

      3, 9, 4,
      3, 4, 2,
      3, 2, 6,
      3, 6, 8,
      3, 8, 9,

      4, 9, 5,
      2, 4, 11,
      6, 2, 10,
      8, 6, 7,
      9, 8, 1,
    ];

    List<double> currentPositions = List.from(basePositions);

    // Cache to store already created midpoints.
    // Key is a 64-bit integer encoding of two indices: (min(i1, i2) << 32) | max(i1, i2).
    Map<int, int> midpointCache = {};

    int getMidpoint(int p1, int p2) {
      final int key = p1 < p2 ? (p1 << 32) | p2 : (p2 << 32) | p1;
      if (midpointCache.containsKey(key)) {
        return midpointCache[key]!;
      }

      final double x1 = currentPositions[p1 * 3];
      final double y1 = currentPositions[p1 * 3 + 1];
      final double z1 = currentPositions[p1 * 3 + 2];

      final double x2 = currentPositions[p2 * 3];
      final double y2 = currentPositions[p2 * 3 + 1];
      final double z2 = currentPositions[p2 * 3 + 2];

      double mx = (x1 + x2) / 2.0;
      double my = (y1 + y2) / 2.0;
      double mz = (z1 + z2) / 2.0;

      // Project midpoint onto the unit sphere.
      final double len = math.sqrt(mx * mx + my * my + mz * mz);
      mx /= len;
      my /= len;
      mz /= len;

      final int newIndex = currentPositions.length ~/ 3;
      currentPositions.add(mx);
      currentPositions.add(my);
      currentPositions.add(mz);

      midpointCache[key] = newIndex;
      return newIndex;
    }

    // Subdivide the mesh N times.
    for (int level = 0; level < subdivisionLevel; level++) {
      final List<int> nextIndices = [];
      midpointCache.clear();

      for (int i = 0; i < currentIndices.length; i += 3) {
        final int v1 = currentIndices[i];
        final int v2 = currentIndices[i + 1];
        final int v3 = currentIndices[i + 2];

        final int a = getMidpoint(v1, v2);
        final int b = getMidpoint(v2, v3);
        final int c = getMidpoint(v3, v1);

        nextIndices.addAll([v1, a, c]);
        nextIndices.addAll([v2, b, a]);
        nextIndices.addAll([v3, c, b]);
        nextIndices.addAll([a, b, c]);
      }
      currentIndices = nextIndices;
    }

    // Positions, UVs, and indices for the final seamless mesh.
    final List<double> finalPositions = [];
    final List<double> finalTexCoords = [];
    final List<int> finalIndices = [];

    // Cache to share final vertices with identical positions and texture coordinates.
    final Map<String, int> finalVertexCache = {};

    int addFinalVertex(double x, double y, double z, double u, double v) {
      // Key contains position and UV coordinates formatted to 7 decimal places
      // to resolve double precision jitter while avoiding duplicates.
      final String key =
          '${x.toStringAsFixed(7)},${y.toStringAsFixed(7)},${z.toStringAsFixed(7)},${u.toStringAsFixed(7)},${v.toStringAsFixed(7)}';
      if (finalVertexCache.containsKey(key)) {
        return finalVertexCache[key]!;
      }

      final int newIndex = finalPositions.length ~/ 3;
      finalPositions.add(x);
      finalPositions.add(y);
      finalPositions.add(z);
      finalTexCoords.add(u);
      finalTexCoords.add(v);

      finalVertexCache[key] = newIndex;
      return newIndex;
    }

    // Process each triangle to calculate spherical UVs, resolve antimeridian seam wrapping,
    // and correctly duplicate vertices at the poles to prevent pinching.
    for (int i = 0; i < currentIndices.length; i += 3) {
      final int idx1 = currentIndices[i];
      final int idx2 = currentIndices[i + 1];
      final int idx3 = currentIndices[i + 2];

      final double x1 = currentPositions[idx1 * 3];
      final double y1 = currentPositions[idx1 * 3 + 1];
      final double z1 = currentPositions[idx1 * 3 + 2];

      final double x2 = currentPositions[idx2 * 3];
      final double y2 = currentPositions[idx2 * 3 + 1];
      final double z2 = currentPositions[idx2 * 3 + 2];

      final double x3 = currentPositions[idx3 * 3];
      final double y3 = currentPositions[idx3 * 3 + 1];
      final double z3 = currentPositions[idx3 * 3 + 2];

      // Calculate initial UV coordinates using standard spherical mapping:
      // u = atan2(y, x) / 2pi + 0.5 (longitude wrapped to [0, 1])
      // v = asin(z) / pi + 0.5 (latitude mapped to [0, 1], with 1 at North Pole, 0 at South Pole)
      double u1 = math.atan2(y1, x1) / (2.0 * math.pi) + 0.5;
      double v1 = math.asin(z1) / math.pi + 0.5;

      double u2 = math.atan2(y2, x2) / (2.0 * math.pi) + 0.5;
      double v2 = math.asin(z2) / math.pi + 0.5;

      double u3 = math.atan2(y3, x3) / (2.0 * math.pi) + 0.5;
      double v3 = math.asin(z3) / math.pi + 0.5;

      // Handle seam crossing.
      // If the difference in longitude coordinates is greater than 0.5, the triangle
      // crosses the antimeridian (the seam where x < 0 and y wraps between negative and positive).
      // We shift coordinates that wrapped below 0.5 by +1.0.
      final double maxU = math.max(u1, math.max(u2, u3));
      final double minU = math.min(u1, math.min(u2, u3));

      if (maxU - minU > 0.5) {
        if (u1 < 0.5) u1 += 1.0;
        if (u2 < 0.5) u2 += 1.0;
        if (u3 < 0.5) u3 += 1.0;
      }

      // Handle poles.
      // At the exact poles (z = 1 or z = -1), longitude is undefined because x = y = 0.
      // To prevent texture pinching, the pole vertex must be duplicated per triangle,
      // setting its longitude to the average of the other two non-polar vertices in that triangle.
      const double epsilon = 1e-6;
      final bool isPole1 = (1.0 - z1.abs()) < epsilon;
      final bool isPole2 = (1.0 - z2.abs()) < epsilon;
      final bool isPole3 = (1.0 - z3.abs()) < epsilon;

      if (isPole1) {
        u1 = (isPole2 ? u3 : (isPole3 ? u2 : (u2 + u3) / 2.0));
      }
      if (isPole2) {
        u2 = (isPole1 ? u3 : (isPole3 ? u1 : (u1 + u3) / 2.0));
      }
      if (isPole3) {
        u3 = (isPole1 ? v1.isNaN ? 0.0 : u2 : (isPole2 ? u1 : (u1 + u2) / 2.0));
      }

      final int newIdx1 = addFinalVertex(x1, y1, z1, u1, v1);
      final int newIdx2 = addFinalVertex(x2, y2, z2, u2, v2);
      final int newIdx3 = addFinalVertex(x3, y3, z3, u3, v3);

      finalIndices.add(newIdx1);
      finalIndices.add(newIdx2);
      finalIndices.add(newIdx3);
    }

    return GlobeMesh(
      positions: Float32List.fromList(finalPositions),
      texCoords: Float32List.fromList(finalTexCoords),
      indices: Uint16List.fromList(finalIndices),
    );
  }
}
