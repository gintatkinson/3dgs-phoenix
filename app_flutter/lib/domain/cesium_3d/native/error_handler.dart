
class CesiumInitializationException implements Exception {
  final String message;
  CesiumInitializationException(this.message);
  @override
  String toString() => 'CesiumInitializationException: $message';
}

class CesiumCameraException implements Exception {
  final String message;
  CesiumCameraException(this.message);
  @override
  String toString() => 'CesiumCameraException: $message';
}

class CesiumTileException implements Exception {
  final String message;
  CesiumTileException(this.message);
  @override
  String toString() => 'CesiumTileException: $message';
}

class CesiumMemoryException implements Exception {
  final String message;
  CesiumMemoryException(this.message);
  @override
  String toString() => 'CesiumMemoryException: $message';
}

class CesiumPickException implements Exception {
  final String message;
  CesiumPickException(this.message);
  @override
  String toString() => 'CesiumPickException: $message';
}

class CesiumFatalException implements Exception {
  final String message;
  CesiumFatalException(this.message);
  @override
  String toString() => 'CesiumFatalException: $message';
}

int checkStatus(int status) {
  if (status == -1) throw CesiumInitializationException('Initialization failed');
  if (status == -2) throw CesiumCameraException('Camera operation failed');
  if (status == -3) throw CesiumTileException('Tile operation failed');
  if (status == -4) throw CesiumMemoryException('Memory allocation failed');
  if (status == -5) throw CesiumPickException('Pick/raycast failed');
  if (status == -100) throw CesiumFatalException('Fatal internal error');
  return status;
}

class TileTimeoutException implements Exception {
  final String message;
  TileTimeoutException(this.message);
  @override
  String toString() => 'TileTimeoutException: $message';
}

class CesiumError {
  final int code;
  final String message;
  CesiumError(this.code, this.message);
  @override
  String toString() => 'CesiumError(code: $code, message: $message)';
}
