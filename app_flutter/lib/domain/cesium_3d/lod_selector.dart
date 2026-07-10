/// Selector for level of detail (LOD) check based on Screen Space Error (SSE).
class LodSelector {
  /// The maximum Screen Space Error threshold allowed before splitting.
  final double threshold;

  /// Creates a [LodSelector] with an optional [threshold].
  const LodSelector({this.threshold = 16.0});

  /// Determines if a tile at the given [zoom], [x], and [y] coordinates should split
  /// based on Screen Space Error (SSE).
  ///
  /// SSE = (tileWidth / cameraAlt) * viewportWidth
  /// where tileWidth = 40075016.68 / (1 << zoom).
  bool shouldSplit(int zoom, int x, int y, double cameraAlt, double viewportWidth) {
    if (cameraAlt <= 0.0) {
      // If the camera is at or below ground level, we split the tile to get max detail.
      return true;
    }
    final double tileWidth = 40075016.68 / (1 << zoom);
    final double sse = (tileWidth / cameraAlt) * viewportWidth;
    return sse > threshold;
  }
}
