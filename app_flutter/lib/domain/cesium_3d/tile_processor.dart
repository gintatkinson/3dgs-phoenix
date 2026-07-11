import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app_flutter/domain/cesium_3d/gltf_parser.dart';
import 'package:app_flutter/domain/cesium_3d/renderers/tile_atlas.dart';

/// Represents the geometry data of a 3D tile, including positions,
/// texture coordinates, and indices.
class TileGeometry {
  /// Flat array of vertex positions in model space: [x0, y0, z0, x1, y1, z1, ...]
  final Float32List positions;

  /// Flat array of texture mapping coordinates: [u0, v0, u1, v1, ...]
  final Float32List texCoords;

  /// Array of vertex indices defining the triangles: [i0, i1, i2, ...]
  final Uint16List indices;

  /// Creates a new [TileGeometry] instance.
  TileGeometry({
    required this.positions,
    required this.texCoords,
    required this.indices,
  });
}

/// A local cache for storing parsed 3D tile geometry.
class TileGeometryCache {
  final Map<String, TileGeometry> _cache = {};

  /// Exposes the underlying cache map.
  Map<String, TileGeometry> get cache => _cache;

  /// Caches the geometry of a parsed tile under the given [tileId].
  void put(String tileId, TileGeometry geometry) {
    _cache[tileId] = geometry;
  }

  /// Retrieves the geometry of a parsed tile, or null if not cached.
  TileGeometry? get(String tileId) {
    return _cache[tileId];
  }

  /// Removes a cached tile geometry.
  void remove(String tileId) {
    _cache.remove(tileId);
  }

  /// Clears all cached tile geometries.
  void clear() {
    _cache.clear();
  }

  /// Checks if the cache contains the geometry of a tile.
  bool contains(String tileId) => _cache.containsKey(tileId);

  /// Returns the number of cached geometry entries.
  int get length => _cache.length;
}

/// Coordinates the processing of binary glTF (GLB) tile data.
///
/// Handles parsing the GLB (offloading to a background isolate for files larger
/// than 100KB), caching the parsed geometry, and decoding/uploading textures.
class TileProcessor {
  /// The tile atlas manager used to upload and manage textures.
  final TileAtlas tileAtlas;

  /// The local geometry cache where processed meshes are stored.
  final TileGeometryCache geometryCache;

  /// Creates a new [TileProcessor] instance with the specified [tileAtlas]
  /// and [geometryCache].
  TileProcessor({
    required this.tileAtlas,
    required this.geometryCache,
  });

  /// Processes binary GLB data for a specific tile.
  ///
  /// If [glbBytes] length is greater than 100KB, GLB parsing is run asynchronously
  /// in a separate isolate. Otherwise, it is parsed directly on the main thread.
  /// The parsed geometry is cached in the local cache. If the mesh contains
  /// texture image bytes, they are decoded and uploaded to the [tileAtlas].
  Future<void> processTileData(String tileId, Uint8List glbBytes) async {
    final GltfMesh mesh;
    // 100KB is 100 * 1024 bytes (102,400 bytes).
    if (glbBytes.length > 100 * 1024) {
      mesh = await Isolate.run(() => GltfParser().parseGlb(glbBytes));
    } else {
      mesh = GltfParser().parseGlb(glbBytes);
    }

    final Float32List scaledPositions = Float32List(mesh.positions.length);
    for (int i = 0; i < mesh.positions.length; i++) {
      scaledPositions[i] = mesh.positions[i] / 6378137.0;
    }

    geometryCache.put(
      tileId,
      TileGeometry(
        positions: scaledPositions,
        texCoords: mesh.texCoords,
        indices: mesh.indices,
      ),
    );

    if (mesh.imageBytes != null) {
      final codec = await ui.instantiateImageCodec(mesh.imageBytes!);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      tileAtlas.getOrCreateTile(tileId);
      tileAtlas.setImage(tileId, image);
    }
  }
}
