import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../virtual_camera.dart';
import '../tile_processor.dart';
import 'globe_mesh.dart';
import 'tile_atlas.dart';

/// Renders a 3D unit globe and atmosphere glow using compiled fragment shaders.
class GlobeRenderer {
  /// The compiled globe shader.
  final ui.FragmentShader globeShader;

  /// The compiled atmosphere shader.
  final ui.FragmentShader atmosphereShader;

  /// The globe mesh geometry.
  final GlobeMesh globeMesh;

  /// The tile atlas manager.
  final TileAtlas tileAtlas;

  /// The optional texture image for the tile atlas.
  final ui.Image? atlasTexture;

  /// Optional callback to retrieve the terrain elevation at a given latitude/longitude in degrees.
  final double Function(double lat, double lng)? getElevation;

  /// Optional cache storing the tile geometries to render.
  final TileGeometryCache? geometryCache;

  /// Creates a new [GlobeRenderer] instance.
  GlobeRenderer({
    required this.globeShader,
    required this.atmosphereShader,
    required this.globeMesh,
    required this.tileAtlas,
    this.atlasTexture,
    this.getElevation,
    this.geometryCache,
  });
}

/// CustomPainter that draws the atmosphere and the globe mesh.
class GlobePainter extends CustomPainter {
  /// The globe renderer configuration and data.
  final GlobeRenderer renderer;

  /// The virtual camera representing the user's viewpoint.
  final VirtualCamera camera;

  /// The blend alpha for the globe shader.
  final double blendAlpha;

  /// The color of the atmosphere glow.
  final Color atmosphereColor;

  /// The glow power of the atmosphere shader.
  final double glowPower;

  /// Optional callback to retrieve the terrain elevation at a given latitude/longitude in degrees.
  final double Function(double lat, double lng)? getElevation;

  /// Optional cache storing the tile geometries to render.
  final TileGeometryCache? geometryCache;

  /// Creates a new [GlobePainter] instance.
  GlobePainter({
    required this.renderer,
    required this.camera,
    this.blendAlpha = 1.0,
    this.atmosphereColor = const Color.fromARGB(255, 76, 153, 229), // vec3(0.3, 0.6, 0.9)
    this.glowPower = 2.0,
    this.getElevation,
    this.geometryCache,
  });

  /// Projects a 3D coordinate [vx, vy, vz] (which is already displaced) directly to screen space.
  ui.Offset projectVertex(double vx, double vy, double vz, Size size) {
    final double latRad = camera.latitude * math.pi / 180.0;
    final double lngRad = camera.longitude * math.pi / 180.0;
    final double cRad = math.max(1.01, 1.0 + camera.altitude / 6378137.0);

    final double cx = cRad * math.cos(latRad) * math.cos(lngRad);
    final double cy = cRad * math.cos(latRad) * math.sin(lngRad);
    final double cz = cRad * math.sin(latRad);

    final double ux = math.cos(latRad) * math.cos(lngRad);
    final double uy = math.cos(latRad) * math.sin(lngRad);
    final double uz = math.sin(latRad);

    final double ex = -math.sin(lngRad);
    final double ey = math.cos(lngRad);
    final double ez = 0.0;

    final double nx = -math.sin(latRad) * math.cos(lngRad);
    final double ny = -math.sin(latRad) * math.sin(lngRad);
    final double nz = math.cos(latRad);

    final double rx = vx - cx;
    final double ry = vy - cy;
    final double rz = vz - cz;

    final double xEnu = rx * ex + ry * ey + rz * ez;
    final double yEnu = rx * nx + ry * ny + rz * nz;
    final double zEnu = rx * ux + ry * uy + rz * uz;

    final double hRad = camera.heading * math.pi / 180.0;
    final double cosH = math.cos(hRad);
    final double sinH = math.sin(hRad);
    final double x1 = xEnu * cosH + yEnu * sinH;
    final double y1 = -xEnu * sinH + yEnu * cosH;

    final double pitchRad = (camera.pitch + 90.0) * math.pi / 180.0;
    final double cosP = math.cos(pitchRad);
    final double sinP = math.sin(pitchRad);
    final double xCam = x1;
    final double yCam = y1 * cosP - zEnu * sinP;
    final double zCam = y1 * sinP + zEnu * cosP;

    final double depth = -zCam;
    final double f = size.shortestSide * 0.8;
    final double pScale = f / (depth <= 0.01 ? 0.01 : depth);

    final double screenX = size.width / 2.0 + xCam * pScale;
    final double screenY = size.height / 2.0 - yCam * pScale;

    return ui.Offset(screenX, screenY);
  }

  /// Projects a unit direction vertex [vx, vy, vz] with terrain displacement and camera projection.
  ui.Offset projectVertexWithDisplacement(double vx, double vy, double vz, Size size) {
    final double lat = math.asin(vz.clamp(-1.0, 1.0)) * 180.0 / math.pi;
    final double lng = math.atan2(vy, vx) * 180.0 / math.pi;

    final activeGetElevation = getElevation ?? renderer.getElevation;
    double height = 0.0;
    if (activeGetElevation != null) {
      final double? val = activeGetElevation(lat, lng);
      if (val != null && val.isFinite) {
        height = (val >= -12000.0 && val <= 9000.0) ? val : 0.0;
      }
    }

    final double scale = 1.0 + height / 6378137.0;
    final double dvx = vx * scale;
    final double dvy = vy * scale;
    final double dvz = vz * scale;

    return projectVertex(dvx, dvy, dvz, size);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw atmosphere glow
    final atmosphereShader = renderer.atmosphereShader;
    atmosphereShader.setFloat(0, size.width);
    atmosphereShader.setFloat(1, size.height);
    atmosphereShader.setFloat(2, atmosphereColor.r);
    atmosphereShader.setFloat(3, atmosphereColor.g);
    atmosphereShader.setFloat(4, atmosphereColor.b);
    atmosphereShader.setFloat(5, glowPower);

    final atmospherePaint = Paint()..shader = atmosphereShader;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), atmospherePaint);

    // 2. Project vertices of the GlobeMesh
    final double latRad = camera.latitude * math.pi / 180.0;
    final double lngRad = camera.longitude * math.pi / 180.0;

    // Normalize Earth Radius as 1.0
    // Camera distance from earth center: normalize to earth radius.
    // Earth radius is approx 6,378,137 meters.
    final double cRad = math.max(1.01, 1.0 + camera.altitude / 6378137.0);

    final double cx = cRad * math.cos(latRad) * math.cos(lngRad);
    final double cy = cRad * math.cos(latRad) * math.sin(lngRad);
    final double cz = cRad * math.sin(latRad);

    final List<ui.Offset> projectedPositions = [];
    final List<bool> visible = [];

    for (int i = 0; i < renderer.globeMesh.positions.length; i += 3) {
      final double vx = renderer.globeMesh.positions[i];
      final double vy = renderer.globeMesh.positions[i + 1];
      final double vz = renderer.globeMesh.positions[i + 2];

      projectedPositions.add(projectVertexWithDisplacement(vx, vy, vz, size));

      // Horizon culling check: dot product with camera direction
      final double dot = vx * cx + vy * cy + vz * cz;
      visible.add(dot >= 1.0); // True if vertex is in the visible hemisphere
    }

    // Filter indices
    final List<int> activeIndices = [];
    for (int i = 0; i < renderer.globeMesh.indices.length; i += 3) {
      final int i0 = renderer.globeMesh.indices[i];
      final int i1 = renderer.globeMesh.indices[i + 1];
      final int i2 = renderer.globeMesh.indices[i + 2];

      if (visible[i0] && visible[i1] && visible[i2]) {
        activeIndices.add(i0);
        activeIndices.add(i1);
        activeIndices.add(i2);
      }
    }

    if (activeIndices.isNotEmpty) {
      // Convert texCoords
      final List<ui.Offset> textureCoordinates = [];
      for (int i = 0; i < renderer.globeMesh.texCoords.length; i += 2) {
        textureCoordinates.add(ui.Offset(renderer.globeMesh.texCoords[i], renderer.globeMesh.texCoords[i + 1]));
      }

      final vertices = ui.Vertices(
        ui.VertexMode.triangles,
        projectedPositions,
        textureCoordinates: textureCoordinates,
        indices: activeIndices,
      );

      // 3. Draw globe mesh with globeShader
      final globeShader = renderer.globeShader;
      globeShader.setFloat(0, size.width);
      globeShader.setFloat(1, size.height);
      globeShader.setFloat(2, blendAlpha);
      globeShader.setFloat(3, 0.0); // uOffset.x
      globeShader.setFloat(4, 0.0); // uOffset.y
      globeShader.setFloat(5, 1.0); // uScale.x
      globeShader.setFloat(6, 1.0); // uScale.y
      final double baseAtlasWidth = renderer.atlasTexture != null
          ? renderer.atlasTexture!.width.toDouble()
          : (renderer.tileAtlas.columns * renderer.tileAtlas.slotWidth).toDouble();
      final double baseAtlasHeight = renderer.atlasTexture != null
          ? renderer.atlasTexture!.height.toDouble()
          : (renderer.tileAtlas.rows * renderer.tileAtlas.slotHeight).toDouble();
      globeShader.setFloat(7, baseAtlasWidth);
      globeShader.setFloat(8, baseAtlasHeight);

      if (renderer.atlasTexture != null) {
        globeShader.setImageSampler(0, renderer.atlasTexture!);
      }

      final globePaint = Paint()..shader = globeShader;
      canvas.drawVertices(vertices, BlendMode.srcOver, globePaint);
    }

    // 4. Draw Tile Geometries from Cache
    final activeGeometryCache = geometryCache ?? renderer.geometryCache;
    if (activeGeometryCache != null && activeGeometryCache.cache.isNotEmpty) {
      final globeShader = renderer.globeShader;

      for (final entry in activeGeometryCache.cache.entries) {
        final String tileId = entry.key;
        final TileGeometry tileGeometry = entry.value;

        // Retrieve texture atlas offset and scale
        final AtlasResult atlasResult = renderer.tileAtlas.getOrCreateTile(tileId);

        // Bind uniforms to globeShader
        globeShader.setFloat(0, size.width);
        globeShader.setFloat(1, size.height);
        globeShader.setFloat(2, blendAlpha);
        globeShader.setFloat(3, atlasResult.offset.dx);
        globeShader.setFloat(4, atlasResult.offset.dy);
        globeShader.setFloat(5, atlasResult.scale.width);
        globeShader.setFloat(6, atlasResult.scale.height);
        final double tileAtlasWidth = (renderer.tileAtlas.columns * renderer.tileAtlas.slotWidth).toDouble();
        final double tileAtlasHeight = (renderer.tileAtlas.rows * renderer.tileAtlas.slotHeight).toDouble();
        globeShader.setFloat(7, tileAtlasWidth);
        globeShader.setFloat(8, tileAtlasHeight);

        // Project tile vertices
        final List<ui.Offset> tileProjectedPositions = [];
        final List<bool> tileVisible = [];

        for (int j = 0; j < tileGeometry.positions.length; j += 3) {
          final double vx = tileGeometry.positions[j];
          final double vy = tileGeometry.positions[j + 1];
          final double vz = tileGeometry.positions[j + 2];

          tileProjectedPositions.add(projectVertex(vx, vy, vz, size));

          // Horizon culling check for tile vertices
          final double len = math.sqrt(vx * vx + vy * vy + vz * vz);
          final double ux_v = len == 0.0 ? 0.0 : vx / len;
          final double uy_v = len == 0.0 ? 0.0 : vy / len;
          final double uz_v = len == 0.0 ? 0.0 : vz / len;

          final double dot = ux_v * cx + uy_v * cy + uz_v * cz;
          tileVisible.add(dot >= 1.0);
        }

        // Filter indices for the tile
        final List<int> tileActiveIndices = [];
        for (int j = 0; j < tileGeometry.indices.length; j += 3) {
          final int i0 = tileGeometry.indices[j];
          final int i1 = tileGeometry.indices[j + 1];
          final int i2 = tileGeometry.indices[j + 2];

          if (tileVisible[i0] && tileVisible[i1] && tileVisible[i2]) {
            tileActiveIndices.add(i0);
            tileActiveIndices.add(i1);
            tileActiveIndices.add(i2);
          }
        }

        if (tileActiveIndices.isNotEmpty) {
          final List<ui.Offset> tileTextureCoordinates = [];
          for (int j = 0; j < tileGeometry.texCoords.length; j += 2) {
            tileTextureCoordinates.add(ui.Offset(tileGeometry.texCoords[j], tileGeometry.texCoords[j + 1]));
          }

          final tileVertices = ui.Vertices(
            ui.VertexMode.triangles,
            tileProjectedPositions,
            textureCoordinates: tileTextureCoordinates,
            indices: tileActiveIndices,
          );

          if (renderer.atlasTexture != null) {
            globeShader.setImageSampler(0, renderer.atlasTexture!);
          }

          final tilePaint = Paint()..shader = globeShader;
          canvas.drawVertices(tileVertices, BlendMode.srcOver, tilePaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant GlobePainter oldDelegate) {
    return oldDelegate.renderer != renderer ||
        oldDelegate.camera != camera ||
        oldDelegate.blendAlpha != blendAlpha ||
        oldDelegate.atmosphereColor != atmosphereColor ||
        oldDelegate.glowPower != glowPower ||
        oldDelegate.getElevation != getElevation ||
        oldDelegate.geometryCache != geometryCache;
  }
}

/// Convenience viewport widget that loads shaders and displays the 3D globe.
class Scene3DGlobeViewport extends StatefulWidget {
  /// The virtual camera for the viewport.
  final VirtualCamera camera;

  /// The globe mesh geometry.
  final GlobeMesh globeMesh;

  /// The tile atlas manager.
  final TileAtlas tileAtlas;

  /// The optional texture image for the tile atlas.
  final ui.Image? atlasTexture;

  /// The blend alpha for the globe.
  final double blendAlpha;

  /// The color of the atmosphere glow.
  final Color atmosphereColor;

  /// The glow power of the atmosphere.
  final double glowPower;

  /// Optional callback to retrieve the terrain elevation at a given latitude/longitude in degrees.
  final double Function(double lat, double lng)? getElevation;

  /// Optional cache storing the tile geometries to render.
  final TileGeometryCache? geometryCache;

  /// Creates a new [Scene3DGlobeViewport] instance.
  const Scene3DGlobeViewport({
    super.key,
    required this.camera,
    required this.globeMesh,
    required this.tileAtlas,
    this.atlasTexture,
    this.blendAlpha = 1.0,
    this.atmosphereColor = const Color.fromARGB(255, 76, 153, 229),
    this.glowPower = 2.0,
    this.getElevation,
    this.geometryCache,
  });

  @override
  State<Scene3DGlobeViewport> createState() => _Scene3DGlobeViewportState();
}

class _Scene3DGlobeViewportState extends State<Scene3DGlobeViewport> {
  ui.FragmentShader? _globeShader;
  ui.FragmentShader? _atmosphereShader;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadShaders();
  }

  Future<void> _loadShaders() async {
    try {
      final globeProgram = await ui.FragmentProgram.fromAsset('shaders/globe.frag');
      final atmosphereProgram = await ui.FragmentProgram.fromAsset('shaders/atmosphere.frag');
      if (mounted) {
        setState(() {
          _globeShader = globeProgram.fragmentShader();
          _atmosphereShader = atmosphereProgram.fragmentShader();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text('Error loading shaders: $_error'));
    }
    final renderer = GlobeRenderer(
      globeShader: _globeShader!,
      atmosphereShader: _atmosphereShader!,
      globeMesh: widget.globeMesh,
      tileAtlas: widget.tileAtlas,
      atlasTexture: widget.atlasTexture,
      getElevation: widget.getElevation,
      geometryCache: widget.geometryCache,
    );
    return CustomPaint(
      painter: GlobePainter(
        renderer: renderer,
        camera: widget.camera,
        blendAlpha: widget.blendAlpha,
        atmosphereColor: widget.atmosphereColor,
        glowPower: widget.glowPower,
        getElevation: widget.getElevation,
        geometryCache: widget.geometryCache,
      ),
      child: const SizedBox.expand(),
    );
  }
}
