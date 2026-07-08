import 'dart:math' as math;
import 'dart:ui';

class TriangleMetrics {
  final double area;
  final double signedArea;
  final double maxEdge;
  final double minEdge;
  final double aspectNumRatio;
  final double qualityMetric;

  TriangleMetrics({
    required this.area,
    required this.signedArea,
    required this.maxEdge,
    required this.minEdge,
    required this.aspectNumRatio,
    required this.qualityMetric,
  });
}

class MeshGeometryValidator {
  static void validate({
    required List<Offset> positions,
    required List<int> indices,
    double maxSpikeEdgeRatio = 40.0,
    double minQualityThreshold = 0.005,
    bool checkWinding = true,
  }) {
    if (indices.isEmpty) return;
    assert(indices.length % 3 == 0, 'Indices length must be a multiple of 3.');

    final List<TriangleMetrics> triMetrics = [];
    final List<double> allEdgeLengths = [];

    for (int i = 0; i < indices.length; i += 3) {
      final p0 = positions[indices[i]];
      final p1 = positions[indices[i + 1]];
      final p2 = positions[indices[i + 2]];

      if (!p0.dx.isFinite || !p0.dy.isFinite ||
          !p1.dx.isFinite || !p1.dy.isFinite ||
          !p2.dx.isFinite || !p2.dy.isFinite) {
        throw Exception('Coordinate Explosion: Projected vertex coordinate is NaN or Infinite.');
      }

      final e0 = p1 - p0;
      final e1 = p2 - p1;
      final e2 = p0 - p2;

      final a = e0.distance;
      final b = e1.distance;
      final c = e2.distance;

      allEdgeLengths.addAll([a, b, c]);

      final signedArea = 0.5 * ((p1.dx - p0.dx) * (p2.dy - p0.dy) - (p2.dx - p0.dx) * (p1.dy - p0.dy));
      final area = signedArea.abs();

      final maxEdge = math.max(a, math.max(b, c));
      final minEdge = math.min(a, math.min(b, c));

      final sumSqEdges = a * a + b * b + c * c;
      final quality = sumSqEdges > 0.0 ? (4.0 * math.sqrt(3.0) * area) / sumSqEdges : 0.0;

      triMetrics.add(TriangleMetrics(
        area: area,
        signedArea: signedArea,
        maxEdge: maxEdge,
        minEdge: minEdge,
        aspectNumRatio: minEdge > 0.0 ? maxEdge / minEdge : double.infinity,
        qualityMetric: quality,
      ));
    }

    allEdgeLengths.sort();
    final medianEdge = allEdgeLengths[allEdgeLengths.length ~/ 2];
    final refEdge = medianEdge > 0.1 ? medianEdge : 1.0;

    for (int i = 0; i < triMetrics.length; i++) {
      final metrics = triMetrics[i];
      if (metrics.maxEdge / refEdge > maxSpikeEdgeRatio) {
        throw Exception(
          'Mesh Spike Detected: Triangle $i has a maximum edge length of '
          '${metrics.maxEdge.toStringAsFixed(2)}px, which is '
          '${(metrics.maxEdge / refEdge).toStringAsFixed(1)}x the median edge length ($medianEdge px).'
        );
      }

      if (metrics.qualityMetric < minQualityThreshold && metrics.area > 5.0) {
        throw Exception(
          'Sliver Triangle Detected: Triangle $i has quality metric '
          '${metrics.qualityMetric.toStringAsFixed(4)} (below threshold $minQualityThreshold).'
        );
      }
    }

    if (checkWinding && triMetrics.isNotEmpty) {
      int posCount = 0;
      int negCount = 0;
      for (final metrics in triMetrics) {
        if (metrics.signedArea > 0.01) {
          posCount++;
        } else if (metrics.signedArea < -0.01) {
          negCount++;
        }
      }

      if (posCount > 0 && negCount > 0) {
        throw Exception(
          'Mesh Folding/Fanning Detected: Mixed winding orientations in screen space. '
          'CCW Triangles: $posCount, CW Triangles: $negCount.'
        );
      }
    }
  }
}
