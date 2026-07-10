import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:app_flutter/domain/cesium_3d/renderers/globe_mesh.dart';

void main() {
  group('GlobeMesh Tests', () {
    test('generateIcosahedron subdivision level 0 (base icosahedron)', () {
      final mesh = GlobeMesh.generateIcosahedron(subdivisionLevel: 0);

      // Expected base icosahedron counts:
      // Triangles: 20
      // Indices: 60
      expect(mesh.indices.length, equals(60));
      expect(mesh.positions.length % 3, equals(0));
      expect(mesh.texCoords.length % 2, equals(0));

      final numVertices = mesh.positions.length ~/ 3;
      expect(numVertices, equals(15)); // 12 + 3 duplicated for seam/poles

      // Verify vertices are normalized to unit sphere
      for (int i = 0; i < numVertices; i++) {
        final x = mesh.positions[i * 3];
        final y = mesh.positions[i * 3 + 1];
        final z = mesh.positions[i * 3 + 2];
        final len = math.sqrt(x * x + y * y + z * z);
        expect(len, closeTo(1.0, 1e-5));
      }

      // Verify indices are within range
      for (final idx in mesh.indices) {
        expect(idx >= 0 && idx < numVertices, isTrue);
      }

      // Verify UV coordinates are valid
      for (int i = 0; i < numVertices; i++) {
        final u = mesh.texCoords[i * 2];
        final v = mesh.texCoords[i * 2 + 1];
        expect(u >= 0.0 && u <= 2.0, isTrue);
        expect(v >= 0.0 && v <= 1.0, isTrue);
      }
    });

    test('generateIcosahedron subdivision level 5 and 6 verification', () {
      final mesh5 = GlobeMesh.generateIcosahedron(subdivisionLevel: 5);
      expect(mesh5.positions.length ~/ 3, equals(10346));
      expect(mesh5.indices.length, equals(61440));

      final mesh6 = GlobeMesh.generateIcosahedron(subdivisionLevel: 6);
      expect(mesh6.positions.length ~/ 3, equals(41162));
      expect(mesh6.indices.length, equals(245760));

      // Verify all indices in level 6 fit in Uint16 (less than 65536)
      final numVertices = mesh6.positions.length ~/ 3;
      expect(numVertices, lessThan(65536));
      for (final idx in mesh6.indices) {
        expect(idx >= 0 && idx < numVertices, isTrue);
      }
    });

    test('validate argument constraints', () {
      expect(
        () => GlobeMesh.generateIcosahedron(subdivisionLevel: -1),
        throwsArgumentError,
      );
    });
  });
}
