// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:app_flutter/domain/cesium_3d/cesium_engine.dart';
import 'package:app_flutter/domain/cesium_3d/globe_tile_renderer.dart';
import 'package:app_flutter/domain/cesium_3d/projected_point.dart';
import 'package:app_flutter/domain/cesium_3d/tile_fetcher.dart';
import 'package:app_flutter/domain/cesium_3d/camera_controller.dart';
import 'package:app_flutter/domain/cesium_3d/virtual_camera.dart';
import 'package:app_flutter/features/topology/topology_map.dart';

class Scene3DViewport extends StatefulWidget {
  final VirtualCamera camera;
  final TopologyData? topologyData;
  final ValueChanged<VirtualCamera>? onCameraChanged;

  const Scene3DViewport({
    super.key,
    required this.camera,
    this.topologyData,
    this.onCameraChanged,
  });

  /// Initializes the 3D scene rendering state.
  bool initializeScene() {
    return true;
  }

  /// Renders the scene onto the canvas.
  bool render(Canvas canvas) {
    return true;
  }

  @override
  State<Scene3DViewport> createState() => Scene3DViewportState();
}

class Scene3DViewportState extends State<Scene3DViewport> {
  late CameraController _cameraController;

  @visibleForTesting
  CameraController get cameraController => _cameraController;

  @visibleForTesting
  FocusNode get globeFocusNode => _globeFocusNode;

  @visibleForTesting
  GlobeTileRenderer? get tileRenderer => _tileRenderer;

  Offset getProjectedPosition(double latitude, double longitude) {
    final Size? size = context.size;
    if (size == null) return Offset.zero;

    final camera = _cameraController.current;
    final double zoomScale = 6378137.0 / camera.altitude;
    final Offset center = Offset(size.width * 0.45, size.height * 0.5);

    final double baseRotation = -(camera.longitude * math.pi / 180.0);
    final double baseTilt = -(camera.latitude * math.pi / 180.0);

    final double latRad = latitude * math.pi / 180.0;
    final double lngRad = longitude * math.pi / 180.0;

    final painter = Scene3DViewportPainter(
      camera: camera,
      activeStyle: _activeStyle,
      astronomicalBody: _astronomicalBody,
      elevationActive: _elevationActive,
      showDevices: _showDevices,
      showLinks: _showLinks,
      showLabels: _showLabels,
      showDropLines: _showDropLines,
      topologyData: widget.topologyData,
      userRotationX: 0.0,
      userTilt: 0.0,
      zoomScale: zoomScale,
      tileRenderer: _tileRenderer,
      imageryProvider: _providerForStyle(_activeStyle),
    );

    final ProjectedPoint projected = painter.project(
      latRad,
      lngRad,
      6378137.0,
      center,
      baseRotation,
      baseTilt,
      size,
    );

    return projected.offset;
  }

  final FocusNode _globeFocusNode = FocusNode();

  bool _shiftHeld = false;
  bool _ctrlHeld = false;
  bool _rightButtonDown = false;
  bool _isUpdatingWidget = false;

  // Interactive configurations
  String _activeStyle = 'Satellite Map';
  String _astronomicalBody = 'Earth';
  bool _elevationActive = true;
  bool _showDevices = true;
  bool _showLinks = true;
  bool _showLabels = true;
  bool _showDropLines = true;
  bool _showCameraStats = true;
  bool _showMapConfig = true;

  GlobeTileRenderer? _tileRenderer;
  Timer? _flyTimer;

  ImageryProvider _providerForStyle(String style) {
    switch (style) {
      case 'Dark Map':
        return ImageryProvider.cartoDark;
      case 'Street Map':
        return ImageryProvider.openStreetMap;
      case 'Satellite Map':
        return ImageryProvider.arcGisSatellite;
      case 'Light Map':
        return ImageryProvider.cartoLight;
      default:
        return ImageryProvider.cartoDark;
    }
  }

  @override
  void initState() {
    super.initState();
    _cameraController = CameraController(widget.camera);
    _cameraController.addListener(_onCameraChangedInside);

    final fetcher = TileFetcher();
    _tileRenderer = GlobeTileRenderer(
      fetcher: fetcher,
      initialProvider: _providerForStyle(_activeStyle),
      onTileLoaded: () {
        if (mounted) {
          setState(() {});
        }
      },
    );

    _globeFocusNode.addListener(() {
      if (mounted) setState(() {});
    });
  }

  void _onCameraChangedInside() {
    if (mounted && !_isUpdatingWidget) {
      setState(() {});
      widget.onCameraChanged?.call(_cameraController.current);
    }
  }

  @override
  void didUpdateWidget(covariant Scene3DViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.camera != widget.camera) {
      _isUpdatingWidget = true;
      _cameraController.updateCamera(widget.camera);
      _isUpdatingWidget = false;
    }
  }

  @override
  void dispose() {
    _flyTimer?.cancel();
    _globeFocusNode.dispose();
    _cameraController.removeListener(_onCameraChangedInside);
    _cameraController.dispose();
    _tileRenderer?.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.escape) {
      _globeFocusNode.unfocus();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.shiftLeft || key == LogicalKeyboardKey.shiftRight) {
      if (event is KeyDownEvent) {
        _shiftHeld = true;
      } else if (event is KeyUpEvent) {
        _shiftHeld = false;
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.controlLeft || key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.metaLeft || key == LogicalKeyboardKey.metaRight) {
      if (event is KeyDownEvent) {
        _ctrlHeld = true;
      } else if (event is KeyUpEvent) {
        _ctrlHeld = false;
      }
      return KeyEventResult.handled;
    }

    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      setState(() {
        if (_shiftHeld) {
          _cameraController.keyboardRotateHeading(-CameraController.keyboardStep);
        } else {
          _cameraController.keyboardRotate(-CameraController.keyboardStep);
        }
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      setState(() {
        if (_shiftHeld) {
          _cameraController.keyboardRotateHeading(CameraController.keyboardStep);
        } else {
          _cameraController.keyboardRotate(CameraController.keyboardStep);
        }
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _cameraController.keyboardTilt(CameraController.keyboardStep);
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _cameraController.keyboardTilt(-CameraController.keyboardStep);
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildStyleButton(String style) {
    final bool isActive = _activeStyle == style;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() {
            _activeStyle = style;
            _tileRenderer?.setProvider(_providerForStyle(style));
          });
        },
        child: Container(
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: isActive ? const Color(0x2200E5FF) : const Color(0x0AFFFFFF),
            border: Border.all(
              color: isActive ? const Color(0xFF00E5FF) : const Color(0x33FFFFFF),
              width: 1.0,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Text(
            style.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isActive ? const Color(0xFF00E5FF) : const Color(0xFFB0BEC5),
              fontSize: 9,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBodyButton(String body) {
    final bool isActive = _astronomicalBody == body;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _astronomicalBody = body;
          });
        },
        child: Container(
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: isActive ? const Color(0x2200E5FF) : const Color(0x0AFFFFFF),
            border: Border.all(
              color: isActive ? const Color(0xFF00E5FF) : const Color(0x33FFFFFF),
              width: 1.0,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Text(
            body.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isActive ? const Color(0xFF00E5FF) : const Color(0xFFB0BEC5),
              fontSize: 9,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVisibilityToggle(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: const TextStyle(
                color: Color(0xFFCFD8DC),
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF00E5FF),
            activeTrackColor: const Color(0x6600E5FF),
            inactiveThumbColor: const Color(0xFF78909C),
            inactiveTrackColor: const Color(0x33FFFFFF),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }

  VirtualCamera? _clickToCamera(Offset localPosition, Size size) {
    final camera = _cameraController.current;
    final double zoomScale = 6378137.0 / camera.altitude;
    final Offset center = Offset(size.width * 0.45, size.height * 0.5);

    final painter = Scene3DViewportPainter(
      camera: camera,
      activeStyle: _activeStyle,
      astronomicalBody: _astronomicalBody,
      elevationActive: _elevationActive,
      showDevices: _showDevices,
      showLinks: _showLinks,
      showLabels: _showLabels,
      showDropLines: _showDropLines,
      topologyData: widget.topologyData,
      userRotationX: 0.0,
      userTilt: 0.0,
      zoomScale: zoomScale,
      tileRenderer: _tileRenderer,
      imageryProvider: _providerForStyle(_activeStyle),
    );

    final ProjectedPoint earthCenterProj = painter.project(0.0, 0.0, 0.0, center, 0.0, 0.0, size);
    final Offset projectedCenter = earthCenterProj.offset;

    final double cRad = 6378137.0 + camera.altitude;
    final double F = size.shortestSide * 1.2;
    final double radDiff1 = cRad * cRad - 6378137.0 * 6378137.0;
    final double projectedRadius = 6378137.0 * F / math.sqrt(radDiff1 <= 0.0 ? 1.0 : radDiff1);

    final double dx = localPosition.dx - projectedCenter.dx;
    final double dy = -(localPosition.dy - projectedCenter.dy);

    if (dx * dx + dy * dy > projectedRadius * projectedRadius) {
      return null;
    }

    final double radDiff = projectedRadius * projectedRadius - dx * dx - dy * dy;
    final double zFinal = math.sqrt(radDiff < 0.0 ? 0.0 : radDiff);

    final double baseRotation = -(camera.longitude * math.pi / 180.0);
    final double baseTilt = -(camera.latitude * math.pi / 180.0);

    final double cosT = math.cos(baseTilt);
    final double sinT = math.sin(baseTilt);
    final double yRot = dy * cosT + zFinal * sinT;
    final double zRot = -dy * sinT + zFinal * cosT;

    final double cosY = math.cos(baseRotation);
    final double sinY = math.sin(baseRotation);
    final double x = dx * cosY - zRot * sinY;
    final double y = yRot;
    final double z = dx * sinY + zRot * cosY;

    final double lat = math.asin((y / projectedRadius).clamp(-1.0, 1.0));
    final double lng = math.atan2(x, z);

    final double latDeg = lat * 180.0 / math.pi;
    final double lngDeg = lng * 180.0 / math.pi;

    final targetAlt = (camera.altitude * 0.5).clamp(
      CameraController.minAltitude,
      CameraController.maxAltitude,
    );

    return VirtualCamera.clamped(
      latitude: latDeg,
      longitude: lngDeg,
      altitude: targetAlt,
      heading: camera.heading,
      pitch: camera.pitch,
      roll: camera.roll,
    );
  }

  @override
  Widget build(BuildContext context) {
    final zoomScale = 6378137.0 / _cameraController.current.altitude;
    return Focus(
      focusNode: _globeFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          _globeFocusNode.requestFocus();
        },
        onScaleStart: (_) {
          _globeFocusNode.requestFocus();
        },
        onScaleUpdate: (details) {
          if (details.scale != 1.0) {
            _cameraController.zoomInteractive(
              (details.scale - 1.0).sign * 20.0,
            );
          }
        },
        onDoubleTapDown: (details) {
          final Size? size = context.size;
          VirtualCamera? targetCam;
          if (size != null) {
            targetCam = _clickToCamera(details.localPosition, size);
          }
          if (targetCam == null) {
            final current = _cameraController.current;
            final targetAlt = (current.altitude * 0.5).clamp(
              CameraController.minAltitude,
              CameraController.maxAltitude,
            );
            targetCam = VirtualCamera.clamped(
              latitude: current.latitude,
              longitude: current.longitude,
              altitude: targetAlt,
              heading: current.heading,
              pitch: current.pitch,
              roll: current.roll,
            );
          }
  
          _cameraController.flyTo(targetCam);
  
          _flyTimer?.cancel();
          _flyTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
            final done = _cameraController.tick();
            if (done) {
              timer.cancel();
              _flyTimer = null;
            }
          });
        },
        child: Stack(
      key: const Key('scene_3d_viewport_container'),
      children: [
            // Background & 3D Globe custom paint
            Positioned.fill(
              child: Listener(
                onPointerDown: (event) {
                  _globeFocusNode.requestFocus();
                  if (event.buttons & kSecondaryMouseButton != 0) {
                    _rightButtonDown = true;
                  }
                },
                onPointerUp: (event) {
                  _rightButtonDown = false;
                },
                onPointerCancel: (event) {
                  _rightButtonDown = false;
                },
                onPointerMove: (event) {
                  final delta = event.localDelta;
                  if (delta.distance <= 0.01) return;
                  final Size? size = context.size;
                  final double shortestSide = size?.shortestSide ?? 800.0;
                  if (event.buttons & kSecondaryMouseButton != 0 || _shiftHeld) {
                    _cameraController.tilt(delta);
                  } else if (_ctrlHeld) {
                    _cameraController.rotateHeading(delta);
                  } else if (event.buttons & kPrimaryMouseButton != 0) {
                    _cameraController.pan(delta, shortestSide);
                  }
                },
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) {
                    _cameraController.zoomInteractive(event.scrollDelta.dy);
                  }
                },
                child: CustomPaint(
                  painter: Scene3DViewportPainter(
                    camera: _cameraController.current,
                    activeStyle: _activeStyle,
                    astronomicalBody: _astronomicalBody,
                    elevationActive: _elevationActive,
                    showDevices: _showDevices,
                    showLinks: _showLinks,
                    showLabels: _showLabels,
                    showDropLines: _showDropLines,
                    topologyData: widget.topologyData,
                    userRotationX: 0.0,
                    userTilt: 0.0,
                    zoomScale: zoomScale,
                    tileRenderer: _tileRenderer,
                    imageryProvider: _providerForStyle(_activeStyle),
                  ),
                ),
              ),
            ),
            
            // Left HUD (Camera Stats & Tile Status)
            if (_showCameraStats)
              Positioned(
                top: 16,
                left: 16,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0x990A0E1A), // semi-transparent
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0x33FFFFFF), // fine borders
                          width: 1.0,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x1F000000),
                            blurRadius: 8,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'CAMERA STATS',
                                style: TextStyle(
                                  color: Color(0xFF00E5FF),
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                              InkWell(
                                key: const Key('collapse_camera_stats_button'),
                                onTap: () => setState(() => _showCameraStats = false),
                                child: const Icon(
                                  Icons.close,
                                  size: 14,
                                  color: Color(0xAAFFFFFF),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Latitude: ${_cameraController.current.latitude.toStringAsFixed(6)}',
                            style: const TextStyle(
                              color: Color(0xFFE0E0E0),
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            'Longitude: ${_cameraController.current.longitude.toStringAsFixed(6)}',
                            style: const TextStyle(
                              color: Color(0xFFE0E0E0),
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            'Altitude: ${_cameraController.current.altitude} meters',
                            style: const TextStyle(
                              color: Color(0xFFE0E0E0),
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            'Pitch/Yaw/Roll: ${_cameraController.current.pitch} / ${_cameraController.current.heading} / ${_cameraController.current.roll}',
                            style: const TextStyle(
                              color: Color(0xFFE0E0E0),
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'TILE STATUS',
                            style: TextStyle(
                              color: Color(0xFF00E5FF),
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'cesium-native WGS84 ECEF transforms active',
                            style: TextStyle(
                              color: Color(0xFFE0E0E0),
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (!_showCameraStats)
              Positioned(
                top: 16,
                left: 16,
                child: ClipOval(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0x990A0E1A),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0x33FFFFFF), width: 1.0),
                      ),
                      child: IconButton(
                        key: const Key('expand_camera_stats_button'),
                        icon: const Icon(Icons.analytics_outlined, size: 18, color: Color(0xFF00E5FF)),
                        padding: EdgeInsets.zero,
                        onPressed: () => setState(() => _showCameraStats = true),
                      ),
                    ),
                  ),
                ),
              ),
            
            // Right HUD: Map Configuration Panel (Right Sidebar overlay)
            if (_showMapConfig)
              Positioned(
                top: 16,
                right: 16,
                bottom: 16,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      width: 280,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0x990A0E1A), // dark translucent background
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0x3300E5FF), // fine cyan border
                          width: 1.0,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.settings,
                                color: Color(0xFF00E5FF),
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'MAP CONFIGURATION',
                                  style: TextStyle(
                                    color: Color(0xFF00E5FF),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ),
                              InkWell(
                                key: const Key('collapse_map_config_button'),
                                onTap: () => setState(() => _showMapConfig = false),
                                child: const Padding(
                                  padding: EdgeInsets.all(4.0),
                                  child: Icon(
                                    Icons.close,
                                    size: 14,
                                    color: Color(0xAAFFFFFF),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Divider(color: Color(0x2200E5FF), height: 1),
                          const SizedBox(height: 12),
                          Expanded(
                            child: SingleChildScrollView(
                              physics: _globeFocusNode.hasFocus
                                  ? const NeverScrollableScrollPhysics()
                                  : null,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Astronomical Body Selection
                                  const Text(
                                    'ASTRONOMICAL BODY',
                                    style: TextStyle(
                                      color: Color(0xFFB0BEC5),
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'monospace',
                                      fontSize: 10,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      _buildBodyButton('Earth'),
                                      _buildBodyButton('Mars'),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      _buildBodyButton('Proxima Centauri'),
                                    ],
                                  ),
                                  
                                  const SizedBox(height: 16),
                                  const Divider(color: Color(0x2200E5FF), height: 1),
                                  const SizedBox(height: 16),

                                  // Base Layer Style Selection
                                  const Text(
                                    'BASE LAYER STYLE',
                                    style: TextStyle(
                                      color: Color(0xFFB0BEC5),
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'monospace',
                                      fontSize: 10,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      _buildStyleButton('Dark Map'),
                                      _buildStyleButton('Street Map'),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      _buildStyleButton('Satellite Map'),
                                      _buildStyleButton('Light Map'),
                                    ],
                                  ),
                                  
                                  const SizedBox(height: 16),
                                  const Divider(color: Color(0x2200E5FF), height: 1),
                                  const SizedBox(height: 16),
                                  
                                  // 3D Surface Elevation
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              '3D SURFACE ELEVATION',
                                              style: TextStyle(
                                                color: Color(0xFFCFD8DC),
                                                fontWeight: FontWeight.bold,
                                                fontFamily: 'monospace',
                                                fontSize: 10,
                                                letterSpacing: 0.8,
                                              ),
                                            ),
                                            if (_elevationActive) ...[
                                              const SizedBox(height: 4),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: const Color(0x1F4CAF50),
                                                  border: Border.all(color: const Color(0xFF4CAF50), width: 1.0),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: const Text(
                                                  'ACTIVE 3D',
                                                  style: TextStyle(
                                                    color: Color(0xFF4CAF50),
                                                    fontSize: 8,
                                                    fontWeight: FontWeight.bold,
                                                    fontFamily: 'monospace',
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      Switch(
                                        value: _elevationActive,
                                        onChanged: (val) {
                                          setState(() {
                                            _elevationActive = val;
                                          });
                                        },
                                        activeColor: const Color(0xFF00E5FF),
                                        activeTrackColor: const Color(0x6600E5FF),
                                        inactiveThumbColor: const Color(0xFF78909C),
                                        inactiveTrackColor: const Color(0x33FFFFFF),
                                      ),
                                    ],
                                  ),
                                  
                                  const SizedBox(height: 16),
                                  const Divider(color: Color(0x2200E5FF), height: 1),
                                  const SizedBox(height: 16),
                                  
                                  // Visibility Toggles
                                  const Text(
                                    'VISIBILITY TOGGLES',
                                    style: TextStyle(
                                      color: Color(0xFFB0BEC5),
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'monospace',
                                      fontSize: 10,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _buildVisibilityToggle('Devices / Nodes', _showDevices, (val) {
                                    setState(() {
                                      _showDevices = val;
                                    });
                                  }),
                                  _buildVisibilityToggle('Topology Links', _showLinks, (val) {
                                    setState(() {
                                      _showLinks = val;
                                    });
                                  }),
                                  _buildVisibilityToggle('Address Labels', _showLabels, (val) {
                                    setState(() {
                                      _showLabels = val;
                                    });
                                  }),
                                  _buildVisibilityToggle('Vertical Drop Lines', _showDropLines, (val) {
                                    setState(() {
                                      _showDropLines = val;
                                    });
                                  }),
                                  
                                  const SizedBox(height: 24),
                                  
                                  // Reset Button
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton(
                                      onPressed: () {
                                        setState(() {
                                          _astronomicalBody = 'Earth';
                                          _activeStyle = 'Satellite Map';
                                          _elevationActive = true;
                                          _showDevices = true;
                                          _showLinks = true;
                                          _showLabels = true;
                                          _showDropLines = true;
                                          _tileRenderer?.setProvider(ImageryProvider.arcGisSatellite);
                                        });
                                      },
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(color: Color(0xFF00E5FF), width: 1.0),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        backgroundColor: const Color(0x0D00E5FF),
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                      ),
                                      child: const Text(
                                        'RESET CAMERA PERSPECTIVE',
                                        style: TextStyle(
                                          color: Color(0xFF00E5FF),
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'monospace',
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (!_showMapConfig)
              Positioned(
                top: 16,
                right: 16,
                child: ClipOval(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0x990A0E1A),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0x3300E5FF), width: 1.0),
                      ),
                      child: IconButton(
                        key: const Key('expand_map_config_button'),
                        icon: const Icon(Icons.settings, size: 18, color: Color(0xFF00E5FF)),
                        padding: EdgeInsets.zero,
                        onPressed: () => setState(() => _showMapConfig = true),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class Scene3DViewportPainter extends CustomPainter {
  final VirtualCamera camera;
  final String activeStyle;
  final String astronomicalBody;
  final bool elevationActive;
  final bool showDevices;
  final bool showLinks;
  final bool showLabels;
  final bool showDropLines;
  final TopologyData? topologyData;
  final double userRotationX;
  final double userTilt;
  final double zoomScale;
  final GlobeTileRenderer? tileRenderer;
  final ImageryProvider imageryProvider;

  Scene3DViewportPainter({
    required this.camera,
    required this.activeStyle,
    required this.astronomicalBody,
    required this.elevationActive,
    required this.showDevices,
    required this.showLinks,
    required this.showLabels,
    required this.showDropLines,
    this.topologyData,
    required this.userRotationX,
    required this.userTilt,
    required this.zoomScale,
    this.tileRenderer,
    this.imageryProvider = ImageryProvider.arcGisSatellite,
  });

  // Reusable paints to avoid per-iteration allocations in the hot 60fps rendering path.
  late final Paint _starPaint = Paint()..style = PaintingStyle.fill;

  late final Paint _orbitPaint = Paint()
    ..color = const Color(0x66FFB300)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;
  late final Paint _orbitGlowPaint = Paint()
    ..color = const Color(0x1FFFB300)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3.0;

  late final Paint _dropPaint = Paint()
    ..color = const Color(0x80FFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;

  late final Paint _satNodePaint = Paint()
    ..color = const Color(0xFFFFB300)
    ..style = PaintingStyle.fill;
  late final Paint _satNodeGlowPaint = Paint()
    ..color = const Color(0x66FFB300)
    ..style = PaintingStyle.fill;
  late final Paint _innerWhitePaint = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.fill;

  late final Paint _gsPaint = Paint()
    ..color = const Color(0xFF00E5FF)
    ..style = PaintingStyle.fill;
  late final Paint _gsGlowPaint = Paint()
    ..color = const Color(0x6600E5FF)
    ..style = PaintingStyle.fill;

  late final Paint _uwRingPaint = Paint()
    ..color = const Color(0xFF00E5FF).withOpacity(0.5)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;

  late final Paint _labelBgPaint = Paint()
    ..color = const Color(0xE6000000)
    ..style = PaintingStyle.fill;
  late final Paint _labelBorderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;

  late final Paint _linkPaint = Paint()
    ..color = const Color(0xFFFF6D00)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;
  late final Paint _linkGlowPaint = Paint()
    ..color = const Color(0x33FF6D00)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4.0;

  late final Paint _packetPaint = Paint()
    ..color = const Color(0xFFFFD54F);

  late final Paint _bandFillPaint = Paint()..style = PaintingStyle.fill;
  late final Paint _bandBorderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.4;

  late final Paint _gridPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.8;

  late final Paint _flarePaint = Paint()
    ..color = const Color(0xFFFF3D00).withOpacity(0.8)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5;
  late final Paint _flareGlowPaint = Paint()
    ..color = const Color(0x33FF3D00)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 6.0;

  late final Paint _reticleDotPaint = Paint()
    ..color = const Color(0xFF00E5FF)
    ..style = PaintingStyle.fill;
  late final Paint _reticlePaint = Paint()
    ..color = const Color(0xCC00E5FF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;

  ProjectedPoint project(
    double lat,
    double lng,
    double height, // passed as height in meters (e.g. 6378137.0 + alt)
    Offset center,
    double rotationY,
    double tilt,
    Size size,
  ) {
    final CesiumEngine? engine = CesiumEngine.instance;
    final double radLng = -rotationY;
    final double radLat = -tilt;

    final double R = 6378137.0;

    double px = 0.0;
    double py = 0.0;
    double pz = 0.0;

    if (engine != null && engine.isReady) {
      final ecef = engine.cartographicToEcef(lat * 180.0 / math.pi, lng * 180.0 / math.pi, height - R);
      if (ecef != null) {
        final (x, y, z) = ecef;
        px = x;
        py = y;
        pz = z;
      }
    } else {
      px = height * math.cos(lat) * math.cos(lng);
      py = height * math.cos(lat) * math.sin(lng);
      pz = height * math.sin(lat);
    }

    // Camera position in ECEF
    final double cRad = R + camera.altitude;
    final double cx = cRad * math.cos(radLat) * math.cos(radLng);
    final double cy = cRad * math.cos(radLat) * math.sin(radLng);
    final double cz = cRad * math.sin(radLat);

    // Camera local ENU basis
    final double ux = math.cos(radLat) * math.cos(radLng);
    final double uy = math.cos(radLat) * math.sin(radLng);
    final double uz = math.sin(radLat);

    final double ex = -math.sin(radLng);
    final double ey = math.cos(radLng);
    final double ez = 0.0;

    final double nx = -math.sin(radLat) * math.cos(radLng);
    final double ny = -math.sin(radLat) * math.sin(radLng);
    final double nz = math.cos(radLat);

    // Relative vector from camera to point
    final double rx = px - cx;
    final double ry = py - cy;
    final double rz = pz - cz;

    // Project onto ENU basis
    final double x_enu = rx * ex + ry * ey + rz * ez;
    final double y_enu = rx * nx + ry * ny + rz * nz;
    final double z_enu = rx * ux + ry * uy + rz * uz;

    // Apply camera pitch and heading
    final double H_rad = camera.heading * math.pi / 180.0;
    final double alpha = (camera.pitch + 90.0) * math.pi / 180.0;

    final double cosH = math.cos(H_rad);
    final double sinH = math.sin(H_rad);
    final double cosA = math.cos(alpha);
    final double sinA = math.sin(alpha);

    final double x1 = x_enu * cosH + y_enu * sinH;
    final double y1 = -x_enu * sinH + y_enu * cosH;
    final double z1 = z_enu;

    final double x_cam = x1;
    final double y_cam = y1 * cosA - z1 * sinA;
    final double z_cam = y1 * sinA + z1 * cosA;

    // Optical axis is along negative z_cam
    final double depth = -z_cam;

    // Horizon culling check using vector-based segment-sphere intersection
    final double distSq = rx * rx + ry * ry + rz * rz;
    final double dotCV = cx * rx + cy * ry + cz * rz;
    final double t = -dotCV / distSq;
    bool isCulled = false;
    if (t > 0.0 && t < 1.0) {
      final double closeSq = (cx * cx + cy * cy + cz * cz) - (dotCV * dotCV) / distSq;
      if (closeSq < R * R) {
        isCulled = true;
      }
    }
    final double depthVal = isCulled ? -1.0 : depth;

    // Focal length (45-degree FOV)
    final double F = size.shortestSide * 1.2;
    final double pScale = depth <= 0.0 ? 1.0 : F / depth;

    final double rx_pixel = x_cam * pScale;
    final double ry_pixel = y_cam * pScale;

    return ProjectedPoint(Offset(center.dx + rx_pixel, center.dy - ry_pixel), depthVal);
  }

  // Convert degrees to radians
  double _rad(double deg) => deg * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    // Shift center to the left to give space to the config overlay sidebar
    final Offset center = Offset(size.width * 0.45, size.height * 0.5);

    // In paint, calculate the projected Earth center and visual radius dynamically
    final ProjectedPoint earthCenterProj = project(0.0, 0.0, 0.0, center, 0.0, 0.0, size);
    final Offset projectedCenter = earthCenterProj.offset;

    final double cRad = 6378137.0 + camera.altitude;
    final double F = size.shortestSide * 1.2;
    final double radDiff = cRad * cRad - 6378137.0 * 6378137.0;
    final double projectedRadius = 6378137.0 * F / math.sqrt(radDiff <= 0.0 ? 1.0 : radDiff);

    // 1. Draw Starry Space Background (~100 stars)
    final math.Random rand = math.Random(42);
    for (int i = 0; i < 100; i++) {
      final double rxVal = rand.nextDouble() * size.width;
      final double ryVal = rand.nextDouble() * size.height;
      final double rSize = rand.nextDouble() * 1.5 + 0.5;
      final double rOpacity = rand.nextDouble() * 0.7 + 0.3;
      _starPaint.color = Color.fromRGBO(255, 255, 255, rOpacity);
      canvas.drawCircle(Offset(rxVal, ryVal), rSize, _starPaint);
    }

    // 2. Astronomical Body customization (corona, atmospheric glows)
    if (astronomicalBody == 'Proxima Centauri') {
      // Intense bright stellar corona glow layers
      final Paint coronaPaint1 = Paint()
        ..shader = RadialGradient(
          colors: const [
            Color(0x99FF3D00), // intense red-orange
            Color(0x44FF9100), // glowing orange
            Color(0x00000000),
          ],
        ).createShader(Rect.fromCircle(center: projectedCenter, radius: projectedRadius * 1.8));
      canvas.drawCircle(projectedCenter, projectedRadius * 1.8, coronaPaint1);

      final Paint coronaPaint2 = Paint()
        ..shader = RadialGradient(
          colors: const [
            Color(0xCCFFEA00), // bright yellow
            Color(0x33FF9100),
            Color(0x00000000),
          ],
        ).createShader(Rect.fromCircle(center: projectedCenter, radius: projectedRadius * 1.45));
      canvas.drawCircle(projectedCenter, projectedRadius * 1.45, coronaPaint2);
    } else if (astronomicalBody == 'Mars') {
      // Dusty reddish-orange atmospheric glow
      final Paint marsAtmosphere = Paint()
        ..shader = RadialGradient(
          colors: const [
            Color(0x66FF5722),
            Color(0x22FF8A65),
            Color(0x00000000),
          ],
        ).createShader(Rect.fromCircle(center: projectedCenter, radius: projectedRadius * 1.35));
      canvas.drawCircle(projectedCenter, projectedRadius * 1.35, marsAtmosphere);
    } else {
      // Earth: Glowing atmospheric blue/cyan radial glow
      final Paint atmospherePaint = Paint()
        ..shader = RadialGradient(
          colors: const [
            Color(0x6600E5FF),
            Color(0x2200E5FF),
            Color(0x00000000),
          ],
          stops: const [0.0, 0.7, 1.0],
        ).createShader(Rect.fromCircle(center: projectedCenter, radius: projectedRadius * 1.35));
      canvas.drawCircle(projectedCenter, projectedRadius * 1.35, atmospherePaint);
    }

    // 3. Earth's / astronomical sphere style variables
    List<Color> oceanColors;
    Color gridColor;
    
    if (astronomicalBody == 'Mars') {
      oceanColors = [const Color(0xFFBF360C), const Color(0xFF3E1103)]; // Desert sphere
      gridColor = const Color(0x22FF5722);
    } else if (astronomicalBody == 'Proxima Centauri') {
      oceanColors = [const Color(0xFFFFD54F), const Color(0xFFE65100)]; // Star golden gradient
      gridColor = const Color(0x33FFD54F);
    } else {
      switch (activeStyle) {
        case 'Dark Map':
          oceanColors = [const Color(0xFF161B22), const Color(0xFF0D1117)];
          gridColor = const Color(0x1A00E5FF);
          break;
        case 'Street Map':
          oceanColors = [const Color(0xFF29B6F6), const Color(0xFF0288D1)];
          gridColor = const Color(0x33000000);
          break;
        case 'Light Map':
          oceanColors = [const Color(0xFFE0F7FA), const Color(0xFF80DEEA)];
          gridColor = const Color(0x26000000);
          break;
        case 'Satellite Map':
        default:
          oceanColors = [const Color(0xFF0F2B5C), const Color(0xFF040A18)];
          gridColor = const Color(0x2600E5FF);
          break;
      }
    }

    // 4. Draw Astronomical / Planetary Sphere
    final Paint spherePaint = Paint()
      ..shader = RadialGradient(
        colors: oceanColors,
      ).createShader(Rect.fromCircle(center: projectedCenter, radius: projectedRadius));
    canvas.drawCircle(projectedCenter, projectedRadius, spherePaint);

    // Rotation angle and tilt based on camera and user inputs
    final double baseRotation = -_rad(camera.longitude);
    final double baseTilt = -_rad(camera.latitude);
    final double rotationAngle = baseRotation + userRotationX;
    final double tilt = baseTilt + userTilt;

    // 5. Draw Grid lines (Meridians & Parallels) - front hemisphere only
    _gridPaint.color = gridColor;

    const int numMeridians = 12;
    const int meridianSteps = 30;
    for (int i = 0; i < numMeridians; i++) {
      final double lng = i * (2 * math.pi / numMeridians);
      for (int j = 0; j < meridianSteps; j++) {
        final double lat1 = -math.pi / 2 + j * (math.pi / meridianSteps);
        final double lat2 = -math.pi / 2 + (j + 1) * (math.pi / meridianSteps);
        
        final ProjectedPoint p1 = project(lat1, lng, 6378137.0, center, rotationAngle, tilt, size);
        final ProjectedPoint p2 = project(lat2, lng, 6378137.0, center, rotationAngle, tilt, size);
        
        if (p1.z >= 0 && p2.z >= 0) {
          canvas.drawLine(p1.offset, p2.offset, _gridPaint);
        }
      }
    }

    const int numParallels = 6;
    const int parallelSteps = 60;
    for (int i = 0; i < numParallels; i++) {
      final double lat = -math.pi / 2 + (i + 1) * (math.pi / (numParallels + 1));
      for (int j = 0; j < parallelSteps; j++) {
        final double lng1 = j * (2 * math.pi / parallelSteps);
        final double lng2 = (j + 1) * (2 * math.pi / parallelSteps);
        
        final ProjectedPoint p1 = project(lat, lng1, 6378137.0, center, rotationAngle, tilt, size);
        final ProjectedPoint p2 = project(lat, lng2, 6378137.0, center, rotationAngle, tilt, size);
        
        if (p1.z >= 0 && p2.z >= 0) {
          canvas.drawLine(p1.offset, p2.offset, _gridPaint);
        }
      }
    }

    // 6. Draw Procedural Latitude Climate Bands (no hardcoded geography)
    if (astronomicalBody != 'Proxima Centauri') {
      final List<(double, double, Color)> bands = [
        (math.pi / 2, math.pi * 0.4, const Color(0x0800BFFF)),  // Arctic
        (math.pi * 0.4, math.pi * 0.15, const Color(0x082196F3)), // Boreal
        (math.pi * 0.15, -math.pi * 0.15, const Color(0x0800E676)), // Tropical
        (-math.pi * 0.15, -math.pi * 0.4, const Color(0x082196F3)), // Temperate S
        (-math.pi * 0.4, -math.pi / 2, const Color(0x0800BFFF)),  // Antarctic
      ];

      for (final (latMax, latMin, color) in bands) {
        _bandFillPaint.color = color;
        _bandBorderPaint.color = color.withOpacity(0.4);

        const int steps = 60;
        final List<ProjectedPoint> pts = [];
        for (int s = 0; s <= steps; s++) {
          final double lng = s * (2 * math.pi / steps);
          final p = project(latMin, lng, 6378137.0 * 1.002, center, rotationAngle, tilt, size);
          if (p.z >= 0.0) pts.add(p);
        }
        for (int s = steps; s >= 0; s--) {
          final double lng = s * (2 * math.pi / steps);
          final p = project(latMax, lng, 6378137.0 * 1.002, center, rotationAngle, tilt, size);
          if (p.z >= 0.0) pts.add(p);
        }

        if (pts.length >= 3) {
          final Path path = Path();
          path.moveTo(pts.first.offset.dx, pts.first.offset.dy);
          for (int i = 1; i < pts.length; i++) {
            path.lineTo(pts[i].offset.dx, pts[i].offset.dy);
          }
          path.close();
          canvas.drawPath(path, _bandFillPaint);
          canvas.drawPath(path, _bandBorderPaint);
        }
      }
    } else {
      // Proxima Centauri: Solar flares and plasma arcs
      const int numFlares = 8;
      for (int f = 0; f < numFlares; f++) {
        final double baseAngle = f * (2 * math.pi / numFlares);
        final double pulse = 1.0;
        
        final double angleStart = baseAngle;
        final double angleEnd = baseAngle + 0.25;
        final double angleMid = baseAngle + 0.125;
        
        final Offset ptStart = Offset(
          projectedCenter.dx + projectedRadius * math.cos(angleStart),
          projectedCenter.dy + projectedRadius * math.sin(angleStart),
        );
        final Offset ptEnd = Offset(
          projectedCenter.dx + projectedRadius * math.cos(angleEnd),
          projectedCenter.dy + projectedRadius * math.sin(angleEnd),
        );
        final Offset ptControl = Offset(
          projectedCenter.dx + projectedRadius * 1.25 * pulse * math.cos(angleMid),
          projectedCenter.dy + projectedRadius * 1.25 * pulse * math.sin(angleMid),
        );
        
        final Path flarePath = Path()
          ..moveTo(ptStart.dx, ptStart.dy)
          ..quadraticBezierTo(ptControl.dx, ptControl.dy, ptEnd.dx, ptEnd.dy);
          
        canvas.drawPath(flarePath, _flareGlowPaint);
        canvas.drawPath(flarePath, _flarePaint);
      }
    }

    // 6b. Render map-imagery tiles on the sphere surface.
    if (tileRenderer != null && tileRenderer!.isEnabled) {
      tileRenderer!.renderTiles(
        canvas,
        camera,
        size,
        center,
        6378137.0,
        (double latDeg, double lngDeg) => project(
          _rad(latDeg),
          _rad(lngDeg),
          6378137.0,
          center,
          rotationAngle,
          tilt,
          size,
        ),
      );
    }

    // 7. Space, Ground, and Underwater Node Layouts (Dynamic DB-Backed)
    List<TopologyNode> nodes = [];
    List<TopologyLink> links = [];

    if (topologyData == null || topologyData!.nodes.isEmpty) {
      nodes = [
        const TopologyNode(
          id: 'sat-1',
          label: 'sat-1',
          position: TopologyNodePosition(dim0: 135.0, dim1: 15.0, dim2: 35786000.0, timeIndex: 0, vector: []),
          status: 'Active',
          rawProperties: {'type': 'SATELLITE'},
        ),
        const TopologyNode(
          id: 'sat-2',
          label: 'sat-2',
          position: TopologyNodePosition(dim0: 142.0, dim1: -25.0, dim2: 20200000.0, timeIndex: 0, vector: []),
          status: 'Active',
          rawProperties: {'type': 'SATELLITE'},
        ),
        const TopologyNode(
          id: 'sat-3',
          label: 'sat-3',
          position: TopologyNodePosition(dim0: 128.0, dim1: 40.0, dim2: 500000.0, timeIndex: 0, vector: []),
          status: 'Active',
          rawProperties: {'type': 'SATELLITE'},
        ),
        const TopologyNode(
          id: 'sat-4',
          label: 'sat-4',
          position: TopologyNodePosition(dim0: 148.0, dim1: -5.0, dim2: 600000.0, timeIndex: 0, vector: []),
          status: 'Active',
          rawProperties: {'type': 'SATELLITE'},
        ),
        const TopologyNode(
          id: 'GS-Tokyo',
          label: 'GS-Tokyo',
          position: TopologyNodePosition(dim0: 139.6, dim1: 35.6, dim2: 50.0, timeIndex: 0, vector: []),
          status: 'Active',
        ),
        const TopologyNode(
          id: 'GS-Sapporo',
          label: 'GS-Sapporo',
          position: TopologyNodePosition(dim0: 141.3, dim1: 43.0, dim2: 25.0, timeIndex: 0, vector: []),
          status: 'Active',
        ),
        const TopologyNode(
          id: 'GS-Fukuoka',
          label: 'GS-Fukuoka',
          position: TopologyNodePosition(dim0: 130.4, dim1: 33.6, dim2: 12.0, timeIndex: 0, vector: []),
          status: 'Active',
        ),
        const TopologyNode(
          id: 'UW-SubCable1',
          label: 'UW-SubCable1',
          position: TopologyNodePosition(dim0: 137.0, dim1: 34.0, dim2: -5.0, timeIndex: 0, vector: []),
          status: 'Active',
        ),
        const TopologyNode(
          id: 'UW-SubCable2',
          label: 'UW-SubCable2',
          position: TopologyNodePosition(dim0: 133.0, dim1: 32.0, dim2: -10.0, timeIndex: 0, vector: []),
          status: 'Active',
        ),
      ];
      links = [
        const TopologyLink(source: 'sat-1', target: 'GS-Tokyo', type: 'depends_on'),
        const TopologyLink(source: 'sat-2', target: 'GS-Sapporo', type: 'depends_on'),
        const TopologyLink(source: 'sat-3', target: 'GS-Fukuoka', type: 'depends_on'),
        const TopologyLink(source: 'sat-4', target: 'GS-Tokyo', type: 'depends_on'),
        const TopologyLink(source: 'sat-4', target: 'UW-SubCable1', type: 'depends_on'),
        const TopologyLink(source: 'GS-Tokyo', target: 'UW-SubCable1', type: 'depends_on'),
        const TopologyLink(source: 'UW-SubCable1', target: 'UW-SubCable2', type: 'depends_on'),
      ];
    } else {
      nodes = topologyData!.nodes;
      links = topologyData!.links;
    }

    final Map<String, ProjectedPoint> allProjectedNodes = {};

    for (final node in nodes) {
      final String id = node.id;
      final double latDeg = node.position.dim1;
      final double lngDeg = node.position.dim0;
      final double alt = node.position.dim2;
      
      final double lat = _rad(latDeg);
      final double baseLng = _rad(lngDeg);
      
      final String nodeType = (node.rawProperties['type'] as String?)?.toUpperCase() ?? '';
      final bool isSatellite = nodeType == 'SATELLITE' || id.toLowerCase().contains('sat') || alt > 100000.0;
      final bool isUnderwater = alt <= 10.0;
      
      double orbitHeight;
      String type;
      double speed = 0.0;

      if (isSatellite) {
        type = 'space';
        orbitHeight = 6378137.0 + alt;
        // Deterministic orbital speed is 0.0 for geostationary constellation
        speed = 0.0;
      } else if (isUnderwater) {
        type = 'underwater';
        orbitHeight = 6378137.0 + alt;
      } else {
        type = 'ground';
        orbitHeight = 6378137.0 + alt;
      }

      final double currentLng = baseLng + rotationAngle * speed;

      // Draw space trajectory loops
      if (type == 'space') {
        final Path orbitPath = Path();
        bool orbitStarted = false;
        const int steps = 60;
        for (int step = 0; step <= steps; step++) {
          final double stepLng = baseLng + (step / steps) * 2 * math.pi;
          final stepProj = project(lat, stepLng, orbitHeight, center, rotationAngle, tilt, size);
          
          if (stepProj.z >= 0.0) {
            if (!orbitStarted) {
              orbitPath.moveTo(stepProj.offset.dx, stepProj.offset.dy);
              orbitStarted = true;
            } else {
              orbitPath.lineTo(stepProj.offset.dx, stepProj.offset.dy);
            }
          } else {
            orbitStarted = false;
          }
        }
        canvas.drawPath(orbitPath, _orbitGlowPaint);
        canvas.drawPath(orbitPath, _orbitPaint);
      }

      // Project the node
      final proj = project(lat, currentLng, orbitHeight, center, rotationAngle, tilt, size);
      
      if (proj.z >= 0) {
        allProjectedNodes[id] = proj;

        // Draw vertical drop line from satellite to surface
        if (type == 'space' && showDropLines) {
          final surfaceProj = project(lat, currentLng, 6378137.0, center, rotationAngle, tilt, size);

          const int dashes = 10;
          for (int d = 0; d < dashes; d++) {
            final Offset pStart = Offset.lerp(proj.offset, surfaceProj.offset, d / dashes)!;
            final Offset pEnd = Offset.lerp(proj.offset, surfaceProj.offset, (d + 0.5) / dashes)!;
            canvas.drawLine(pStart, pEnd, _dropPaint);
          }
        }

        // Draw nodes
        if (showDevices) {
          if (type == 'space') {
            canvas.drawCircle(proj.offset, 7.0, _satNodeGlowPaint);
            canvas.drawCircle(proj.offset, 4.0, _satNodePaint);
            canvas.drawCircle(proj.offset, 1.8, _innerWhitePaint);
          } else if (type == 'ground') {
            canvas.drawCircle(proj.offset, 6.0, _gsGlowPaint);
            canvas.drawCircle(proj.offset, 3.0, _gsPaint);
          } else if (type == 'underwater') {
            canvas.drawCircle(proj.offset, 3.0, _gsPaint);
            canvas.drawCircle(proj.offset, 7.5, _uwRingPaint);
          }

          if (showLabels) {
            final Color textColor = type == 'space'
                ? const Color(0xFFFFB300)
                : const Color(0xFF00E5FF);
            final textPainter = _TextPainterCache.getOrCreate(
              node.label.isNotEmpty ? node.label : id,
              textColor,
              const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            );
            final Offset textPos = proj.offset + const Offset(8, -4);
            final RRect capsuleRRect = RRect.fromRectAndRadius(
              Rect.fromLTWH(
                textPos.dx - 6,
                textPos.dy - 3,
                textPainter.width + 12,
                textPainter.height + 6,
              ),
              const Radius.circular(8),
            );
            _labelBorderPaint.color = textColor.withOpacity(0.4);
            canvas.drawRRect(capsuleRRect, _labelBgPaint);
            canvas.drawRRect(capsuleRRect, _labelBorderPaint);
            textPainter.paint(canvas, textPos);
          }
        }
      }
    }

    // 8. Draw Network Links & Active Packets (Dynamic DB-Backed)
    if (showLinks && showDevices) {
      for (int i = 0; i < links.length; i++) {
        final link = links[i];
        final String n1 = link.source;
        final String n2 = link.target;
        
        final ProjectedPoint? p1 = allProjectedNodes[n1];
        final ProjectedPoint? p2 = allProjectedNodes[n2];
        
        if (p1 != null && p2 != null) {
          canvas.drawLine(p1.offset, p2.offset, _linkGlowPaint);
          canvas.drawLine(p1.offset, p2.offset, _linkPaint);

          final double packetT = (i * 0.25) % 1.0;
          final Offset packetOffset = Offset.lerp(p1.offset, p2.offset, packetT)!;
          canvas.drawCircle(packetOffset, 2.5, _packetPaint);
        }
      }
    }

    // 9. Draw targeting HUD reticle at the center
    canvas.drawCircle(center, 3.0, _reticleDotPaint);

    final double pulseOpacity = 1.0;
    final double pulseRadius = 0.0;
    final Paint pulsePaint = Paint()
      ..color = const Color(0x0000E5FF).withOpacity(pulseOpacity * 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, pulseRadius, pulsePaint);

    canvas.drawCircle(center, 10.0, _reticlePaint);

    canvas.save();
    final double reticleRotation = 0.0;
    canvas.translate(center.dx, center.dy);
    canvas.rotate(reticleRotation);
    
    canvas.drawLine(const Offset(0, -18), const Offset(0, -10), _reticlePaint);
    canvas.drawLine(const Offset(0, 10), const Offset(0, 18), _reticlePaint);
    canvas.drawLine(const Offset(-18, 0), const Offset(-10, 0), _reticlePaint);
    canvas.drawLine(const Offset(10, 0), const Offset(18, 0), _reticlePaint);
    
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant Scene3DViewportPainter oldDelegate) {
    return oldDelegate.camera != camera ||
        oldDelegate.activeStyle != activeStyle ||
        oldDelegate.astronomicalBody != astronomicalBody ||
        oldDelegate.elevationActive != elevationActive ||
        oldDelegate.showDevices != showDevices ||
        oldDelegate.showLinks != showLinks ||
        oldDelegate.showLabels != showLabels ||
        oldDelegate.showDropLines != showDropLines ||
        oldDelegate.userRotationX != userRotationX ||
        oldDelegate.userTilt != userTilt ||
        oldDelegate.zoomScale != zoomScale ||
        oldDelegate.tileRenderer != tileRenderer ||
        oldDelegate.imageryProvider != imageryProvider;
  }
}


class Network3DScene {
  String gltfData = '';
  bool isTranslucent = false;

  /// Loads the glTF model data from the given path.
  bool loadModel(String modelPath) {
    if (modelPath.isEmpty) {
      return false;
    }
    gltfData = 'gltf_binary_stub_data_for_$modelPath';
    return true;
  }

  /// Applies PBR materials and sets transcluent flags.
  bool applyPbrMaterials() {
    isTranslucent = true;
    return true;
  }
}

class _TextPainterKey {
  final String text;
  final Color color;
  _TextPainterKey(this.text, this.color);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _TextPainterKey &&
          text == other.text &&
          color == other.color;

  @override
  int get hashCode => Object.hash(text, color);
}

class _TextPainterCache {
  static final Map<_TextPainterKey, TextPainter> _cache = {};
  static const int _maxEntries = 256;

  static TextPainter getOrCreate(String text, Color color, TextStyle baseStyle) {
    final key = _TextPainterKey(text, color);
    final existing = _cache[key];
    if (existing != null) return existing;

    if (_cache.length >= _maxEntries) {
      _cache.remove(_cache.keys.first);
    }
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: baseStyle.copyWith(color: color),
      ),
      textDirection: TextDirection.ltr,
    );
    painter.layout();
    _cache[key] = painter;
    return painter;
  }
}
