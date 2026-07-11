import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:app_flutter/domain/cesium_3d/renderers/tile_atlas.dart';
import 'package:app_flutter/domain/cesium_3d/tile_processor.dart';

// 1x1 transparent PNG bytes
final Uint8List tinyPngBytes = base64Decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==");

void main() {
  // Helper to generate a valid mock GLB buffer
  Uint8List createMockGlb({
    required Map<String, dynamic> jsonMap,
    required List<int> binData,
  }) {
    final jsonStr = json.encode(jsonMap);
    final jsonBytes = utf8.encode(jsonStr);

    final jsonPadding = (4 - (jsonBytes.length % 4)) % 4;
    final paddedJsonBytes = Uint8List(jsonBytes.length + jsonPadding);
    paddedJsonBytes.setRange(0, jsonBytes.length, jsonBytes);
    for (int i = 0; i < jsonPadding; i++) {
      paddedJsonBytes[jsonBytes.length + i] = 0x20;
    }

    final binPadding = (4 - (binData.length % 4)) % 4;
    final paddedBinBytes = Uint8List(binData.length + binPadding);
    paddedBinBytes.setAll(0, binData);
    for (int i = 0; i < binPadding; i++) {
      paddedBinBytes[binData.length + i] = 0x00;
    }

    final totalLength = 12 + 8 + paddedJsonBytes.length + 8 + paddedBinBytes.length;
    final glb = Uint8List(totalLength);
    final byteData = ByteData.view(glb.buffer);

    byteData.setUint32(0, 0x46546C67, Endian.little);
    byteData.setUint32(4, 2, Endian.little);
    byteData.setUint32(8, totalLength, Endian.little);

    byteData.setUint32(12, paddedJsonBytes.length, Endian.little);
    byteData.setUint32(16, 0x4E4F534A, Endian.little);
    glb.setRange(20, 20 + paddedJsonBytes.length, paddedJsonBytes);

    final binChunkOffset = 20 + paddedJsonBytes.length;
    byteData.setUint32(binChunkOffset, paddedBinBytes.length, Endian.little);
    byteData.setUint32(binChunkOffset + 4, 0x004E4942, Endian.little);
    glb.setRange(binChunkOffset + 8, binChunkOffset + 8 + paddedBinBytes.length, paddedBinBytes);

    return glb;
  }

  Map<String, dynamic> createValidJsonMap({
    int posCount = 3,
    int texCount = 3,
    int indexCount = 3,
    bool includeImage = false,
  }) {
    final bufferViews = [
      {
        "buffer": 0,
        "byteOffset": 0,
        "byteLength": posCount * 3 * 4,
      },
      {
        "buffer": 0,
        "byteOffset": posCount * 3 * 4,
        "byteLength": texCount * 2 * 4,
      },
      {
        "buffer": 0,
        "byteOffset": (posCount * 3 * 4) + (texCount * 2 * 4),
        "byteLength": indexCount * 2,
      }
    ];

    final accessors = [
      {
        "bufferView": 0,
        "byteOffset": 0,
        "componentType": 5126, // FLOAT
        "count": posCount,
        "type": "VEC3"
      },
      {
        "bufferView": 1,
        "byteOffset": 0,
        "componentType": 5126, // FLOAT
        "count": texCount,
        "type": "VEC2"
      },
      {
        "bufferView": 2,
        "byteOffset": 0,
        "componentType": 5123, // UNSIGNED_SHORT
        "count": indexCount,
        "type": "SCALAR"
      }
    ];

    final images = <Map<String, dynamic>>[];
    if (includeImage) {
      final imgOffset = (posCount * 3 * 4) + (texCount * 2 * 4) + (indexCount * 2);
      final imgOffsetAligned = (imgOffset + 3) & ~3;
      bufferViews.add({
        "buffer": 0,
        "byteOffset": imgOffsetAligned,
        "byteLength": tinyPngBytes.length,
      });
      images.add({
        "bufferView": 3,
        "mimeType": "image/png"
      });
    }

    return {
      "asset": {"version": "2.0"},
      "meshes": [
        {
          "primitives": [
            {
              "attributes": {
                "POSITION": 0,
                "TEXCOORD_0": 1
              },
              "indices": 2
            }
          ]
        }
      ],
      "accessors": accessors,
      "bufferViews": bufferViews,
      "buffers": [
        {"byteLength": 200000}
      ],
      if (images.isNotEmpty) "images": images,
    };
  }

  List<int> createValidBinData({
    int posCount = 3,
    int texCount = 3,
    int indexCount = 3,
    bool includeImage = false,
    int extraPaddingBytes = 0,
  }) {
    final builder = BytesBuilder();

    // Positions: [x0, y0, z0, ...]
    final positions = Float32List(posCount * 3);
    for (int i = 0; i < positions.length; i++) {
      positions[i] = i.toDouble();
    }
    builder.add(positions.buffer.asUint8List());

    // TexCoords: [u0, v0, ...]
    final texCoords = Float32List(texCount * 2);
    for (int i = 0; i < texCoords.length; i++) {
      texCoords[i] = 0.5;
    }
    builder.add(texCoords.buffer.asUint8List());

    // Indices: [i0, i1, i2, ...]
    final indices = Uint16List(indexCount);
    for (int i = 0; i < indices.length; i++) {
      indices[i] = i % posCount;
    }
    builder.add(indices.buffer.asUint8List());

    if (includeImage) {
      final currentLength = builder.length;
      final padding = (4 - (currentLength % 4)) % 4;
      builder.add(Uint8List(padding));
      builder.add(tinyPngBytes);
    }

    if (extraPaddingBytes > 0) {
      builder.add(Uint8List(extraPaddingBytes));
    }

    return builder.toBytes();
  }

  group('TileProcessor Tests', () {
    late TileAtlas tileAtlas;
    late TileGeometryCache geometryCache;
    late TileProcessor processor;

    setUp(() {
      tileAtlas = TileAtlas(columns: 2, rows: 2);
      geometryCache = TileGeometryCache();
      processor = TileProcessor(
        tileAtlas: tileAtlas,
        geometryCache: geometryCache,
      );
    });

    testWidgets('should parse small GLB (<100KB) directly, cache geometry, and upload texture', (WidgetTester tester) async {
      final jsonMap = createValidJsonMap(includeImage: true);
      final binData = createValidBinData(includeImage: true);
      final glb = createMockGlb(jsonMap: jsonMap, binData: binData);

      expect(glb.length, lessThanOrEqualTo(100 * 1024));

      await tester.runAsync(() async {
        await processor.processTileData('tile_small', glb);
      });

      // 1. Verify geometry is inserted into the cache
      expect(geometryCache.contains('tile_small'), isTrue);
      final geometry = geometryCache.get('tile_small')!;
      expect(geometry.positions.length, equals(9)); // 3 vertices * 3 coords
      expect(geometry.texCoords.length, equals(6)); // 3 vertices * 2 coords
      expect(geometry.indices.length, equals(3));

      // 2. Verify image is decoded and uploaded to the atlas slot
      expect(tileAtlas.contains('tile_small'), isTrue);
      expect(tileAtlas.getImageForTile('tile_small'), isA<ui.Image>());
    });

    testWidgets('should parse large GLB (>100KB) in isolate, cache geometry, and upload texture', (WidgetTester tester) async {
      // Create > 100KB GLB by adding extra padding bytes to bin data
      final jsonMap = createValidJsonMap(includeImage: true);
      final binData = createValidBinData(includeImage: true, extraPaddingBytes: 110 * 1024);
      final glb = createMockGlb(jsonMap: jsonMap, binData: binData);

      expect(glb.length, greaterThan(100 * 1024));

      await tester.runAsync(() async {
        await processor.processTileData('tile_large', glb);
      });

      // 1. Verify geometry is inserted into cache
      expect(geometryCache.contains('tile_large'), isTrue);
      final geometry = geometryCache.get('tile_large')!;
      expect(geometry.positions.length, equals(9));
      expect(geometry.texCoords.length, equals(6));
      expect(geometry.indices.length, equals(3));

      // 2. Verify image is decoded and uploaded to the atlas slot
      expect(tileAtlas.contains('tile_large'), isTrue);
      expect(tileAtlas.getImageForTile('tile_large'), isA<ui.Image>());
    });

    testWidgets('should parse GLB without texture, cache geometry, but not upload image', (WidgetTester tester) async {
      final jsonMap = createValidJsonMap(includeImage: false);
      final binData = createValidBinData(includeImage: false);
      final glb = createMockGlb(jsonMap: jsonMap, binData: binData);

      await tester.runAsync(() async {
        await processor.processTileData('tile_no_texture', glb);
      });

      // Verify geometry is cached
      expect(geometryCache.contains('tile_no_texture'), isTrue);

      // Verify no image upload calls were made
      expect(tileAtlas.contains('tile_no_texture'), isFalse);
      expect(tileAtlas.getImageForTile('tile_no_texture'), isNull);
    });
  });
}
