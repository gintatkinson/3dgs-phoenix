class SceneBootstrapper {
  static String? _sceneId;
  static bool _isolatedSceneMode = false;

  /// Parses command-line arguments to check if isolated scene mode is active.
  /// Checks for the presence of `--scene=[id]` in the arguments list.
  /// Stores and returns whether isolated scene mode is active.
  static bool boot(List<String> args) {
    _isolatedSceneMode = false;
    _sceneId = null;
    for (final arg in args) {
      if (arg.startsWith('--scene=')) {
        _sceneId = arg.substring('--scene='.length);
        _isolatedSceneMode = true;
        break;
      }
    }
    return _isolatedSceneMode;
  }

  /// Gets the parsed scene ID, if isolated scene mode is active.
  static String? get sceneId => _sceneId;

  /// Gets whether the isolated scene mode is active.
  static bool get isIsolatedSceneMode => _isolatedSceneMode;
}
