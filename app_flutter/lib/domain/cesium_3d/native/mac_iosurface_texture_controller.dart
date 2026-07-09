import 'package:flutter/services.dart';

/// Controller to communicate with the native macOS texture sharing plugin.
class MacIosurfaceTextureController {
  static const MethodChannel _channel = MethodChannel('3dgs.phoenix/texture_bridge');
  
  int? _textureId;
  
  /// Gets the registered Flutter texture ID, or null if not yet initialized.
  int? get textureId => _textureId;

  /// Initializes the controller by requesting a texture ID registration from the native side.
  Future<void> initialize() async {
    try {
      final int? id = await _channel.invokeMethod<int>('getTextureId');
      _textureId = id;
    } catch (e) {
      print('Failed to register texture: $e');
    }
  }

  /// Sends a frame update signal to bind the given IOSurface pointer to the Flutter texture.
  Future<void> updateFrame(int ioSurfaceRef) async {
    if (_textureId == null) return;
    try {
      await _channel.invokeMethod('updateFrame', {
        'ioSurfaceRef': ioSurfaceRef,
      });
    } catch (e) {
      print('Failed to update frame: $e');
    }
  }
}
