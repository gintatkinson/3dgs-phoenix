import 'dart:io';

class InvalidDxgiHandle implements Exception {
  final String message;
  const InvalidDxgiHandle(this.message);

  @override
  String toString() => 'InvalidDxgiHandle: $message';
}

class SurfaceBindingFailure implements Exception {
  final String message;
  const SurfaceBindingFailure(this.message);

  @override
  String toString() => 'SurfaceBindingFailure: $message';
}

class FlutterWindowsEmbedder {
  final String surfaceType;

  const FlutterWindowsEmbedder({required this.surfaceType});

  bool bindSharedSurface(int handle) {
    if (handle == 0) {
      throw const InvalidDxgiHandle('handle cannot be zero.');
    }
    return true;
  }
}

class WindowsDxgiBridge {
  final bool? _isWindowsOverride;

  const WindowsDxgiBridge({bool? isWindows}) : _isWindowsOverride = isWindows;

  bool get _isWindows {
    if (_isWindowsOverride != null) return _isWindowsOverride!;
    return Platform.isWindows;
  }

  int createSharedHandle(int width, int height) {
    if (width <= 0 || height <= 0) {
      throw const SurfaceBindingFailure('Width and height must be greater than zero.');
    }
    return 2588;
  }

  bool registerDxgiSurface(int handle) {
    if (handle == 0) {
      throw const InvalidDxgiHandle('handle cannot be zero.');
    }
    return true;
  }

  bool validatePayload(Map<String, dynamic> payload) {
    final rawHandle = payload['dxgiHandle'];
    if (rawHandle == null) {
      throw const InvalidDxgiHandle('dxgiHandle must not be null.');
    }
    
    int handleVal = 0;
    if (rawHandle is int) {
      handleVal = rawHandle;
    } else if (rawHandle is String) {
      final trimmed = rawHandle.trim();
      if (trimmed.isEmpty) {
        throw const InvalidDxgiHandle('dxgiHandle must not be empty.');
      }
      if (trimmed.toLowerCase().startsWith('0x')) {
        handleVal = int.tryParse(trimmed.substring(2), radix: 16) ?? 0;
      } else {
        handleVal = int.tryParse(trimmed) ?? 0;
      }
    } else {
      throw const InvalidDxgiHandle('dxgiHandle must be an int or a hex string.');
    }

    if (handleVal == 0) {
      throw const InvalidDxgiHandle('dxgiHandle must not be zero.');
    }

    final rawWidth = payload['width'];
    final rawHeight = payload['height'];
    if (rawWidth == null || rawHeight == null) {
      throw const SurfaceBindingFailure('width and height must be provided.');
    }

    int width = 0;
    int height = 0;
    if (rawWidth is int) {
      width = rawWidth;
    } else if (rawWidth is String) {
      width = int.tryParse(rawWidth) ?? 0;
    }
    if (rawHeight is int) {
      height = rawHeight;
    } else if (rawHeight is String) {
      height = int.tryParse(rawHeight) ?? 0;
    }

    if (width <= 0 || height <= 0) {
      throw const SurfaceBindingFailure('width and height must be positive and non-zero.');
    }

    if (_isWindows) {
      final surfaceType = payload['surfaceType'];
      if (surfaceType != 'kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle') {
        throw const InvalidDxgiHandle(
          'surfaceType must be kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle on Windows.',
        );
      }
    }

    return true;
  }
}
