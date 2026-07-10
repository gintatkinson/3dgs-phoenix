import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../virtual_camera.dart';
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

  /// Creates a new [GlobeRenderer] instance.
  GlobeRenderer({
    required this.globeShader,
    required this.atmosphereShader,
    required this.globeMesh,
    required this.tileAtlas,
    this.atlasTexture,
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

  /// Creates a new [GlobePainter] instance.
  GlobePainter({
    required this.renderer,
    required this.camera,
    this.blendAlpha = 1.0,
    this.atmosphereColor = const Color.fromARGB(255, 76, 153, 229), // vec3(0.3, 0.6, 0.9)
    this.glowPower = 2.0,
  });

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

    // Basis vectors
    final double ux = math.cos(latRad) * math.cos(lngRad);
    final double uy = math.cos(latRad) * math.sin(lngRad);
    final double uz = math.sin(latRad);

    final double ex = -math.sin(lngRad);
    final double ey = math.cos(lngRad);
    final double ez = 0.0;

    final double nx = -math.sin(latRad) * math.cos(lngRad);
    final double ny = -math.sin(latRad) * math.sin(lngRad);
    final double nz = math.cos(latRad);

    final List<ui.Offset> projectedPositions = [];
    final List<bool> visible = [];

    for (int i = 0; i < renderer.globeMesh.positions.length; i += 3) {
      final double vx = renderer.globeMesh.positions[i];
      final double vy = renderer.globeMesh.positions[i + 1];
      final double vz = renderer.globeMesh.positions[i + 2];

      // Relative vector
      final double rx = vx - cx;
      final double ry = vy - cy;
      final double rz = vz - cz;

      // Project onto ENU basis
      final double xEnu = rx * ex + ry * ey + rz * ez;
      final double yEnu = rx * nx + ry * ny + rz * nz;
      final double zEnu = rx * ux + ry * uy + rz * uz;

      // Rotate by heading
      final double hRad = camera.heading * math.pi / 180.0;
      final double cosH = math.cos(hRad);
      final double sinH = math.sin(hRad);
      final double x1 = xEnu * cosH + yEnu * sinH;
      final double y1 = -xEnu * sinH + yEnu * cosH;

      // Rotate by pitch
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

      projectedPositions.add(ui.Offset(screenX, screenY));

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

    if (activeIndices.isEmpty) return;

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

    if (renderer.atlasTexture != null) {
      globeShader.setImageSampler(0, renderer.atlasTexture!);
    }

    final globePaint = Paint()..shader = globeShader;
    canvas.drawVertices(vertices, BlendMode.srcOver, globePaint);
  }

  @override
  bool shouldRepaint(covariant GlobePainter oldDelegate) {
    return oldDelegate.renderer != renderer ||
        oldDelegate.camera != camera ||
        oldDelegate.blendAlpha != blendAlpha ||
        oldDelegate.atmosphereColor != atmosphereColor ||
        oldDelegate.glowPower != glowPower;
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
    );
    return CustomPaint(
      painter: GlobePainter(
        renderer: renderer,
        camera: widget.camera,
        blendAlpha: widget.blendAlpha,
        atmosphereColor: widget.atmosphereColor,
        glowPower: widget.glowPower,
      ),
      child: const SizedBox.expand(),
    );
  }
}
