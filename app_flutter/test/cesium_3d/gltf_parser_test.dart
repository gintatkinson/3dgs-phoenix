import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_flutter/domain/cesium_3d/gltf_parser.dart';

void main() {
  group('GltfParser - GLB Binary Header and Chunk Validation', () {
    test('should throw FormatException when glbBytes is too small to contain a header', () {
      final parser = GltfParser();
      expect(
        () => parser.parseGlb(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
    });

    test('should throw FormatException when magic number is invalid', () {
      final parser = GltfParser();
      // Correct length (12), but magic is incorrect (0x11223344)
      final badMagicGlb = Uint8List(12);
      final byteData = ByteData.view(badMagicGlb.buffer);
      byteData.setUint32(0, 0x11223344, Endian.little);
      byteData.setUint32(4, 2, Endian.little);
      byteData.setUint32(8, 12, Endian.little);

      expect(
        () => parser.parseGlb(badMagicGlb),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Invalid GLB magic number'),
        )),
      );
    });

    test('should throw FormatException when version is not 2', () {
      final parser = GltfParser();
      final badVersionGlb = Uint8List(12);
      final byteData = ByteData.view(badVersionGlb.buffer);
      byteData.setUint32(0, 0x46546C67, Endian.little); // glTF
      byteData.setUint32(4, 1, Endian.little);          // version 1
      byteData.setUint32(8, 12, Endian.little);

      expect(
        () => parser.parseGlb(badVersionGlb),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Unsupported GLB version'),
        )),
      );
    });

    test('should throw FormatException when total file length mismatches byte array length', () {
      final parser = GltfParser();
      final badLenGlb = Uint8List(12);
      final byteData = ByteData.view(badLenGlb.buffer);
      byteData.setUint32(0, 0x46546C67, Endian.little);
      byteData.setUint32(4, 2, Endian.little);
      byteData.setUint32(8, 100, Endian.little); // Header expects 100 bytes, but actual is 12

      expect(
        () => parser.parseGlb(badLenGlb),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('does not match actual byte length'),
        )),
      );
    });

    test('should throw FormatException when chunk boundaries exceed array size', () {
      final parser = GltfParser();
      // Construct a GLB with a chunk length specifying data beyond the array size.
      final glb = Uint8List(20);
      final byteData = ByteData.view(glb.buffer);
      byteData.setUint32(0, 0x46546C67, Endian.little);
      byteData.setUint32(4, 2, Endian.little);
      byteData.setUint32(8, 20, Endian.little);
      byteData.setUint32(12, 10, Endian.little); // Chunk length 10, chunk header (8 bytes) + 12 = 20 => offset + 8 + 10 = 30 > 20
      byteData.setUint32(16, 0x4E4F534A, Endian.little); // JSON chunk type

      expect(
        () => parser.parseGlb(glb),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Chunk data out of bounds'),
        )),
      );
    });

    test('should throw FormatException when missing JSON chunk', () {
      final parser = GltfParser();
      // Construct GLB with only a BIN chunk (no JSON chunk)
      final glb = Uint8List(28);
      final byteData = ByteData.view(glb.buffer);
      byteData.setUint32(0, 0x46546C67, Endian.little);
      byteData.setUint32(4, 2, Endian.little);
      byteData.setUint32(8, 28, Endian.little);
      byteData.setUint32(12, 8, Endian.little);
      byteData.setUint32(16, 0x004E4942, Endian.little); // BIN chunk type

      expect(
        () => parser.parseGlb(glb),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Missing required JSON chunk in GLB'),
        )),
      );
    });
  });

  group('GltfParser - Accessor and Mesh Parsing tests', () {
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
      bool imageByUri = false,
      String? imageUri,
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
        if (imageByUri) {
          images.add({
            "uri": imageUri ?? "data:image/png;base64,AQIDBA==", // mock image data [1, 2, 3, 4]
            "mimeType": "image/png"
          });
        } else {
          final imgOffset = (posCount * 3 * 4) + (texCount * 2 * 4) + (indexCount * 2);
          // Pad image offset to multiple of 4
          final imgOffsetAligned = (imgOffset + 3) & ~3;
          bufferViews.add({
            "buffer": 0,
            "byteOffset": imgOffsetAligned,
            "byteLength": 4,
          });
          images.add({
            "bufferView": 3,
            "mimeType": "image/png"
          });
        }
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
          {"byteLength": 1000}
        ],
        if (images.isNotEmpty) "images": images,
      };
    }

    List<int> createValidBinData({
      int posCount = 3,
      int texCount = 3,
      int indexCount = 3,
      List<int>? indicesOverride,
      bool includeImage = false,
      List<int>? imageBytes,
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
      if (indicesOverride != null) {
        for (int i = 0; i < indices.length; i++) {
          indices[i] = indicesOverride[i];
        }
      } else {
        for (int i = 0; i < indices.length; i++) {
          indices[i] = i % posCount;
        }
      }
      builder.add(indices.buffer.asUint8List());

      if (includeImage) {
        // Pad the builder data to align image offset to multiple of 4
        final currentLength = builder.length;
        final padding = (4 - (currentLength % 4)) % 4;
        builder.add(Uint8List(padding));

        builder.add(imageBytes ?? [10, 20, 30, 40]);
      }

      return builder.toBytes();
    }

    test('should successfully parse valid mesh geometry and texture coordinates', () {
      final jsonMap = createValidJsonMap();
      final binData = createValidBinData();
      final glb = createMockGlb(jsonMap: jsonMap, binData: binData);

      final parser = GltfParser();
      final mesh = parser.parseGlb(glb);

      expect(mesh.positions, equals([0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]));
      expect(mesh.texCoords, equals([0.5, 0.5, 0.5, 0.5, 0.5, 0.5]));
      expect(mesh.indices, equals([0, 1, 2]));
      expect(mesh.imageBytes, isNull);
    });

    test('should successfully extract embedded image bytes from bufferView', () {
      final jsonMap = createValidJsonMap(includeImage: true);
      final binData = createValidBinData(includeImage: true, imageBytes: [100, 101, 102, 103]);
      final glb = createMockGlb(jsonMap: jsonMap, binData: binData);

      final parser = GltfParser();
      final mesh = parser.parseGlb(glb);

      expect(mesh.imageBytes, equals([100, 101, 102, 103]));
    });

    test('should successfully extract embedded image bytes from base64 data URI', () {
      // "data:image/png;base64,AQIDBA==" encodes [1, 2, 3, 4]
      final jsonMap = createValidJsonMap(includeImage: true, imageByUri: true);
      final binData = createValidBinData();
      final glb = createMockGlb(jsonMap: jsonMap, binData: binData);

      final parser = GltfParser();
      final mesh = parser.parseGlb(glb);

      expect(mesh.imageBytes, equals([1, 2, 3, 4]));
    });

    test('should throw FormatException if indices are out of vertex range bounds', () {
      // 3 vertices, so indices must be in [0, 2].
      // We will pass index 3 which is out of bounds.
      final jsonMap = createValidJsonMap();
      final binData = createValidBinData(indicesOverride: [0, 1, 3]);
      final glb = createMockGlb(jsonMap: jsonMap, binData: binData);

      final parser = GltfParser();
      expect(
        () => parser.parseGlb(glb),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('out of valid vertex index bounds'),
        )),
      );
    });

    test('should throw FormatException if bufferView extends beyond BIN chunk boundaries', () {
      final jsonMap = createValidJsonMap();
      // Artificially modify one bufferView to be extremely large in JSON, exceeding BIN chunk size.
      final bufferViews = jsonMap['bufferViews'] as List<dynamic>;
      bufferViews[0]['byteLength'] = 10000;

      final binData = createValidBinData();
      final glb = createMockGlb(jsonMap: jsonMap, binData: binData);

      final parser = GltfParser();
      expect(
        () => parser.parseGlb(glb),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('exceeds BIN chunk bounds'),
        )),
      );
    });

    test('should throw FormatException if accessor extends beyond bufferView boundaries', () {
      final jsonMap = createValidJsonMap();
      // Make accessor count larger than what bufferView byteLength can fit
      final accessors = jsonMap['accessors'] as List<dynamic>;
      accessors[0]['count'] = 100; // expects 100 * 3 * 4 = 1200 bytes, but bufferView byteLength is 36

      final binData = createValidBinData();
      final glb = createMockGlb(jsonMap: jsonMap, binData: binData);

      final parser = GltfParser();
      expect(
        () => parser.parseGlb(glb),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('exceeds bufferView'),
        )),
      );
    });
  });
}
