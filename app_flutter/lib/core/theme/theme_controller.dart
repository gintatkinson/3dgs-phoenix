import 'package:flutter/material.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'app_themes.dart';
import 'theme_service.dart';

/// View-model that owns the current theme mode, colour-scheme index, and
/// persists every change through [ThemeService].
///
/// Exposes a [ChangeNotifier] interface so that UI widgets can react to
/// theme changes via `context.watch<ThemeController>()`. Alternatives:
/// using [ThemeService] directly for read-only access; using
/// [TextScalerController] for font-size changes.
///
/// **State**: updates internal fields and calls `notifyListeners()` on
/// every mutation. Persistence is fire-and-forget (awaited but not exposed).
///
/// **Edge cases**: null inputs are silently ignored; out-of-bounds scheme
/// indices are clamped silently to the first scheme.
class ThemeController extends ChangeNotifier {
  ThemeController(this._themeService);
  final ThemeService _themeService;
  ThemeMode _themeMode = ThemeMode.system;
  int _currentThemeIndex = 0;
  Axis _layoutSplitAxis = Axis.vertical;
  double _panelOpacity = 0.85;
  bool _disposed = false;

  Future<void> _operationQueue = Future.value();

  Future<void> _enqueue(Future<void> Function() operation) {
    return _operationQueue = _operationQueue.then((_) {
      if (_disposed) return Future<void>.value();
      return operation();
    }).catchError((_) {});
  }

  /// Current [ThemeMode] (light / dark / system).
  ThemeMode get themeMode => _themeMode;

  /// Index into [AppThemes.customSchemes] for the active colour scheme.
  ///
  /// Guaranteed to be a valid index after [loadSettings] completes.
  int get currentThemeIndex => _currentThemeIndex;

  /// Current layout split axis orientation.
  Axis get layoutSplitAxis => _layoutSplitAxis;

  /// Panel/overlay opacity between 0.0 and 1.0.
  double get panelOpacity => _panelOpacity;

  /// Convenience getter for the currently selected [FlexSchemeData].
  ///
  /// Reads from [AppThemes.customSchemes] at [currentThemeIndex]. Safe to
  /// call after [loadSettings] because the index is clamped on load.
  FlexSchemeData get currentTheme => AppThemes.customSchemes[_currentThemeIndex];

  /// Loads persisted theme mode and scheme index from [ThemeService].
  ///
  /// Must be called once during app initialisation before the UI reads any
  /// theme state. Calling again resets state. An out-of-bounds persisted
  /// index is silently clamped to 0. Fires `notifyListeners()` on
  /// completion even if values are unchanged.
  Future<void> loadSettings() {
    return _enqueue(() async {
      final mode = await _themeService.loadThemeMode();
      if (_disposed) return;
      _themeMode = mode;

      final scheme = await _themeService.loadThemeScheme();
      if (_disposed) return;
      _currentThemeIndex = scheme;
      if (_currentThemeIndex < 0 || _currentThemeIndex >= AppThemes.customSchemes.length) {
        _currentThemeIndex = 0;
      }

      final axis = await _themeService.loadLayoutSplitAxis();
      if (_disposed) return;
      _layoutSplitAxis = axis;

      final opacity = await _themeService.loadPanelOpacity();
      if (_disposed) return;
      _panelOpacity = opacity;

      notifyListeners();
    });
  }

  /// Updates the theme mode and persists it via [ThemeService].
  ///
  /// No-op when [newThemeMode] is null or matches the current value.
  /// Fires `notifyListeners()` before persisting so the UI updates
  /// immediately. Persistence failure is silently swallowed.
  Future<void> updateThemeMode(ThemeMode? newThemeMode) {
    return _enqueue(() async {
      if (newThemeMode == null || newThemeMode == _themeMode) return;
      _themeMode = newThemeMode;
      notifyListeners();
      await _themeService.saveThemeMode(newThemeMode);
    });
  }

  /// Updates the colour-scheme index and persists it via [ThemeService].
  ///
  /// No-op when [newIndex] is null, matches the current value, or is
  /// outside valid bounds. Fires `notifyListeners()` before persisting.
  /// Persistence failure is silently swallowed.
  Future<void> updateThemeScheme(int? newIndex) {
    return _enqueue(() async {
      if (newIndex == null || newIndex == _currentThemeIndex) return;
      if (newIndex < 0 || newIndex >= AppThemes.customSchemes.length) return;
      _currentThemeIndex = newIndex;
      notifyListeners();
      await _themeService.saveThemeScheme(newIndex);
    });
  }

  /// Updates the layout split axis orientation and persists it via [ThemeService].
  ///
  /// No-op when [newAxis] is null or matches the current value.
  /// Fires `notifyListeners()` before persisting.
  /// Persistence failure is silently swallowed.
  Future<void> updateLayoutSplitAxis(Axis? newAxis) {
    return _enqueue(() async {
      if (newAxis == null || newAxis == _layoutSplitAxis) return;
      _layoutSplitAxis = newAxis;
      notifyListeners();
      await _themeService.saveLayoutSplitAxis(newAxis);
    });
  }

  /// Updates the panel opacity value and persists it via [ThemeService].
  ///
  /// No-op when [newOpacity] is null or matches the current value.
  /// Fires `notifyListeners()` before persisting.
  /// Persistence failure is silently swallowed.
  Future<void> updatePanelOpacity(double? newOpacity) {
    return _enqueue(() async {
      if (newOpacity == null || newOpacity == _panelOpacity) return;
      _panelOpacity = newOpacity;
      notifyListeners();
      await _themeService.savePanelOpacity(newOpacity);
    });
  }

  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
