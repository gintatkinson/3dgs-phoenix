import 'dart:convert';
import 'dart:typed_data';

/// Represents parsed 3D mesh geometry and texture data from a binary glTF (GLB) container.
class GltfMesh {
  /// Flat array of vertex positions in model space: [x0, y0, z0, x1, y1, z1, ...]
  final Float32List positions;

  /// Flat array of texture mapping coordinates: [u0, v0, u1, v1, ...]
  final Float32List texCoords;

  /// Array of vertex indices defining the triangles: [i0, i1, i2, ...]
  final Uint16List indices;

  /// Extracted raw image bytes (PNG/JPEG) of the tile's texture, if present.
  final Uint8List? imageBytes;

  /// Creates a new [GltfMesh] instance.
  GltfMesh({
    required this.positions,
    required this.texCoords,
    required this.indices,
    this.imageBytes,
  });
}

/// A parser for binary glTF (GLB) assets.
///
/// Implements safety-critical boundary checks, magic and version validation,
/// and validates vertex index bounds.
class GltfParser {
  /// Parses a GLB byte buffer and returns a [GltfMesh].
  ///
  /// Throws a [FormatException] if the header, chunks, or accessors are invalid,
  /// or if index values lie outside the valid vertex range.
  GltfMesh parseGlb(Uint8List glbBytes) {
    if (glbBytes.length < 12) {
      throw const FormatException("GLB buffer is too small to contain a header.");
    }

    final byteData = ByteData.view(
      glbBytes.buffer,
      glbBytes.offsetInBytes,
      glbBytes.length,
    );

    // 1. Verify Magic Number ("glTF" in little-endian)
    final magic = byteData.getUint32(0, Endian.little);
    if (magic != 0x46546C67) {
      throw FormatException(
          "Invalid GLB magic number: 0x${magic.toRadixString(16).toUpperCase()}");
    }

    // 2. Verify Version (must be 2)
    final version = byteData.getUint32(4, Endian.little);
    if (version != 2) {
      throw FormatException("Unsupported GLB version: $version");
    }

    // 3. Validate Total File Length
    final totalLength = byteData.getUint32(8, Endian.little);
    if (totalLength != glbBytes.length) {
      throw FormatException(
          "GLB length in header ($totalLength) does not match actual byte length (${glbBytes.length})");
    }

    // 4. Loop chunks to locate JSON and BIN chunks
    int offset = 12;
    Uint8List? jsonBytes;
    Uint8List? binBytes;
    int binChunkDataStartInGlb = -1;

    while (offset < glbBytes.length) {
      if (offset + 8 > glbBytes.length) {
        throw FormatException("Chunk header out of bounds at offset $offset.");
      }

      final chunkLength = byteData.getUint32(offset, Endian.little);
      final chunkType = byteData.getUint32(offset + 4, Endian.little);

      if (offset + 8 + chunkLength > glbBytes.length) {
        throw FormatException(
            "Chunk data out of bounds: chunk length $chunkLength at offset $offset exceeds file bounds.");
      }

      final chunkData = Uint8List.view(
        glbBytes.buffer,
        glbBytes.offsetInBytes + offset + 8,
        chunkLength,
      );

      if (chunkType == 0x4E4F534A) {
        // "JSON"
        jsonBytes = chunkData;
      } else if (chunkType == 0x004E4942) {
        // "BIN"
        binBytes = chunkData;
        binChunkDataStartInGlb = offset + 8;
      }

      offset += 8 + chunkLength;
    }

    if (jsonBytes == null) {
      throw const FormatException("Missing required JSON chunk in GLB.");
    }

    // Initialize binBytes to empty if not present (although usually required for meshes)
    binBytes ??= Uint8List(0);
    if (binChunkDataStartInGlb == -1) {
      binChunkDataStartInGlb = glbBytes.length;
    }

    // 5. Parse JSON Chunk
    final jsonStr = utf8.decode(jsonBytes);
    final jsonMap = json.decode(jsonStr) as Map<String, dynamic>;

    final meshes = jsonMap['meshes'] as List<dynamic>?;
    if (meshes == null || meshes.isEmpty) {
      throw const FormatException("No meshes found in GLB JSON.");
    }
    final mesh = meshes[0] as Map<String, dynamic>?;
    if (mesh == null) {
      throw const FormatException("Mesh at index 0 is null.");
    }
    final primitives = mesh['primitives'] as List<dynamic>?;
    if (primitives == null || primitives.isEmpty) {
      throw const FormatException("No primitives found in mesh.");
    }
    final primitive = primitives[0] as Map<String, dynamic>?;
    if (primitive == null) {
      throw const FormatException("Primitive at index 0 is null.");
    }
    final attributes = primitive['attributes'] as Map<String, dynamic>?;
    if (attributes == null) {
      throw const FormatException("No attributes found in primitive.");
    }

    final positionAccessorIndex = attributes['POSITION'] as int?;
    final texCoordAccessorIndex = attributes['TEXCOORD_0'] as int?;
    final indicesAccessorIndex = primitive['indices'] as int?;

    if (positionAccessorIndex == null) {
      throw const FormatException("POSITION attribute accessor not found.");
    }
    if (texCoordAccessorIndex == null) {
      throw const FormatException("TEXCOORD_0 attribute accessor not found.");
    }
    if (indicesAccessorIndex == null) {
      throw const FormatException("Indices accessor not found.");
    }

    final accessors = jsonMap['accessors'] as List<dynamic>?;
    final bufferViews = jsonMap['bufferViews'] as List<dynamic>?;
    if (accessors == null || bufferViews == null) {
      throw const FormatException("Missing accessors or bufferViews in GLB JSON.");
    }

    // Helper function to extract data from an accessor
    ByteData getAccessorData(
      int accessorIndex,
      List<int> expectedComponentTypes,
      String expectedType,
    ) {
      if (accessorIndex < 0 || accessorIndex >= accessors.length) {
        throw FormatException("Accessor index $accessorIndex out of bounds.");
      }
      final accessor = accessors[accessorIndex] as Map<String, dynamic>;
      final bufferViewIndex = accessor['bufferView'] as int?;
      if (bufferViewIndex == null) {
        throw FormatException(
            "Accessor $accessorIndex has no bufferView (unsupported).");
      }
      if (bufferViewIndex < 0 || bufferViewIndex >= bufferViews.length) {
        throw FormatException(
            "BufferView index $bufferViewIndex out of bounds.");
      }
      final bufferView = bufferViews[bufferViewIndex] as Map<String, dynamic>;

      final count = accessor['count'] as int? ?? 0;
      final componentType = accessor['componentType'] as int?;
      final type = accessor['type'] as String?;

      if (!expectedComponentTypes.contains(componentType)) {
        throw FormatException(
            "Unexpected componentType $componentType for accessor $accessorIndex.");
      }
      if (type != expectedType) {
        throw FormatException(
            "Unexpected type $type for accessor $accessorIndex (expected $expectedType).");
      }

      final bufferIndex = bufferView['buffer'] as int? ?? 0;
      if (bufferIndex != 0) {
        throw FormatException(
            "Unsupported buffer index $bufferIndex (only buffer 0 is supported).");
      }

      final viewByteOffset = bufferView['byteOffset'] as int? ?? 0;
      final viewByteLength = bufferView['byteLength'] as int? ?? 0;
      final accessorByteOffset = accessor['byteOffset'] as int? ?? 0;

      final totalByteOffset = viewByteOffset + accessorByteOffset;

      int componentSize;
      if (componentType == 5126) {
        // FLOAT
        componentSize = 4;
      } else if (componentType == 5123) {
        // UNSIGNED_SHORT
        componentSize = 2;
      } else if (componentType == 5125) {
        // UNSIGNED_INT
        componentSize = 4;
      } else if (componentType == 5121) {
        // UNSIGNED_BYTE
        componentSize = 1;
      } else {
        throw FormatException("Unsupported componentType $componentType.");
      }

      int numComponents;
      if (type == "VEC3") {
        numComponents = 3;
      } else if (type == "VEC2") {
        numComponents = 2;
      } else if (type == "SCALAR") {
        numComponents = 1;
      } else {
        throw FormatException("Unsupported type $type.");
      }

      final elementSize = componentSize * numComponents;
      final expectedByteLength = count * elementSize;

      if (viewByteOffset < 0 || viewByteLength < 0 || accessorByteOffset < 0) {
        throw const FormatException(
            "Negative offset or length in bufferView/accessor.");
      }

      if (viewByteOffset + viewByteLength > binBytes!.length) {
        throw FormatException(
            "bufferView $bufferViewIndex exceeds BIN chunk bounds.");
      }

      if (accessorByteOffset + expectedByteLength > viewByteLength) {
        throw FormatException(
            "Accessor $accessorIndex exceeds bufferView $bufferViewIndex bounds.");
      }

      final startOffsetInGlb = binChunkDataStartInGlb + totalByteOffset;
      final startOffsetInBytes = glbBytes.offsetInBytes + startOffsetInGlb;

      if (startOffsetInBytes % componentSize != 0) {
        final slice = Uint8List.fromList(
          glbBytes.sublist(
              startOffsetInGlb, startOffsetInGlb + expectedByteLength),
        );
        return slice.buffer.asByteData();
      } else {
        return ByteData.view(
          glbBytes.buffer,
          startOffsetInBytes,
          expectedByteLength,
        );
      }
    }

    // 6. Extract Positions
    final posByteData = getAccessorData(positionAccessorIndex, [5126], "VEC3");
    final positions = Float32List(posByteData.lengthInBytes ~/ 4);
    for (int i = 0; i < positions.length; i++) {
      positions[i] = posByteData.getFloat32(i * 4, Endian.little);
    }

    // 7. Extract Texture Coordinates
    final texByteData = getAccessorData(texCoordAccessorIndex, [5126], "VEC2");
    final texCoords = Float32List(texByteData.lengthInBytes ~/ 4);
    for (int i = 0; i < texCoords.length; i++) {
      texCoords[i] = texByteData.getFloat32(i * 4, Endian.little);
    }

    // 8. Extract Indices & Validate bounds
    final indicesAccessor = accessors[indicesAccessorIndex] as Map<String, dynamic>;
    final indicesComponentType = indicesAccessor['componentType'] as int?;
    if (indicesComponentType != 5123 &&
        indicesComponentType != 5125 &&
        indicesComponentType != 5121) {
      throw FormatException(
          "Unsupported indices component type: $indicesComponentType");
    }

    final indicesByteData = getAccessorData(
      indicesAccessorIndex,
      [5121, 5123, 5125],
      "SCALAR",
    );
    final numIndices = indicesAccessor['count'] as int? ?? 0;
    final indices = Uint16List(numIndices);

    final vertexCount = positions.length ~/ 3;

    for (int i = 0; i < numIndices; i++) {
      int indexVal;
      if (indicesComponentType == 5123) {
        indexVal = indicesByteData.getUint16(i * 2, Endian.little);
      } else if (indicesComponentType == 5125) {
        indexVal = indicesByteData.getUint32(i * 4, Endian.little);
      } else {
        indexVal = indicesByteData.getUint8(i);
      }

      if (indexVal < 0 || indexVal >= vertexCount) {
        throw FormatException(
            "Index $indexVal is out of valid vertex index bounds [0, ${vertexCount - 1}].");
      }
      indices[i] = indexVal;
    }

    // 9. Extract embedded image bytes if present
    Uint8List? imageBytes;
    final images = jsonMap['images'] as List<dynamic>?;
    if (images != null && images.isNotEmpty) {
      final image = images[0] as Map<String, dynamic>?;
      if (image != null) {
        final imgBufferViewIndex = image['bufferView'] as int?;
        if (imgBufferViewIndex != null) {
          if (imgBufferViewIndex < 0 || imgBufferViewIndex >= bufferViews.length) {
            throw FormatException(
                "Image bufferView index $imgBufferViewIndex out of bounds.");
          }
          final imgBufferView = bufferViews[imgBufferViewIndex] as Map<String, dynamic>;
          final imgBufferIndex = imgBufferView['buffer'] as int? ?? 0;
          if (imgBufferIndex != 0) {
            throw FormatException(
                "Unsupported image buffer index $imgBufferIndex (only buffer 0 is supported).");
          }
          final imgByteOffset = imgBufferView['byteOffset'] as int? ?? 0;
          final imgByteLength = imgBufferView['byteLength'] as int? ?? 0;

          if (imgByteOffset < 0 || imgByteLength < 0) {
            throw const FormatException(
                "Negative offset or length in image bufferView.");
          }
          if (imgByteOffset + imgByteLength > binBytes.length) {
            throw const FormatException("Image bufferView exceeds BIN chunk bounds.");
          }

          final imgStartOffsetInGlb = binChunkDataStartInGlb + imgByteOffset;
          imageBytes = Uint8List.fromList(
            glbBytes.sublist(
                imgStartOffsetInGlb, imgStartOffsetInGlb + imgByteLength),
          );
        } else {
          final uri = image['uri'] as String?;
          if (uri != null) {
            if (uri.startsWith('data:')) {
              final commaIndex = uri.indexOf(',');
              if (commaIndex != -1) {
                final dataStr = uri.substring(commaIndex + 1);
                if (uri.substring(0, commaIndex).contains('base64')) {
                  imageBytes = base64.decode(dataStr);
                } else {
                  imageBytes = Uint8List.fromList(
                      utf8.encode(Uri.decodeComponent(dataStr)));
                }
              }
            } else {
              throw FormatException(
                  "External image URI '$uri' is not supported in GLB.");
            }
          }
        }
      }
    }

    return GltfMesh(
      positions: positions,
      texCoords: texCoords,
      indices: indices,
      imageBytes: imageBytes,
    );
  }
}
