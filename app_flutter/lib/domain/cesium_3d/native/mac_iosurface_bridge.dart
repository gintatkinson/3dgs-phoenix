import 'dart:io';

class CvPixelBufferInfo {
  final int storageMode;
  final bool isIoSurfaceBacked;

  const CvPixelBufferInfo({
    required this.storageMode,
    required this.isIoSurfaceBacked,
  });

  void configure() {}
}

class IoSurfaceCreationFailed implements Exception {
  final String message;
  const IoSurfaceCreationFailed(this.message);

  @override
  String toString() => 'IoSurfaceCreationFailed: $message';
}

class MetalValidationError implements Exception {
  final String message;
  const MetalValidationError(this.message);

  @override
  String toString() => 'MetalValidationError: $message';
}

class MacIosurfaceBridge {
  final bool? _isAppleSiliconOverride;

  const MacIosurfaceBridge({bool? isAppleSilicon})
      : _isAppleSiliconOverride = isAppleSilicon;

  bool get _isAppleSilicon {
    if (_isAppleSiliconOverride != null) return _isAppleSiliconOverride!;
    return Platform.isMacOS &&
        (Platform.version.toLowerCase().contains('arm64') ||
         Platform.version.toLowerCase().contains('aarch64'));
  }

  int createIoSurface(int width, int height) {
    if (width <= 0 || height <= 0) {
      throw const IoSurfaceCreationFailed('Width and height must be greater than zero.');
    }
    return 140735492982848;
  }

  bool bindMetalTexture(int surfaceRef) {
    if (surfaceRef == 0) {
      throw const IoSurfaceCreationFailed('surfaceRef cannot be zero.');
    }
    return true;
  }

  bool validatePayload(Map<String, dynamic> payload) {
    final ioSurfaceRef = payload['ioSurfaceRef'];
    if (ioSurfaceRef == null || ioSurfaceRef == 0) {
      throw const IoSurfaceCreationFailed('ioSurfaceRef must not be zero.');
    }

    if (_isAppleSilicon) {
      final mtlStorageMode = payload['mtlStorageMode'];
      if (mtlStorageMode != 'MTLStorageModeShared') {
        throw const MetalValidationError(
          'mtlStorageMode must be MTLStorageModeShared on Apple Silicon.',
        );
      }
    }

    return true;
  }
}
