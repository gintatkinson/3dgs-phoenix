import 'dart:ui' as ui;

/// Represents the UV coordinates (offset and scale) of a slot in the tile atlas.
class AtlasResult {
  /// The UV offset of the top-left corner of the slot in normalized coordinates.
  final ui.Offset offset;

  /// The normalized width and height of the slot in the atlas texture.
  final ui.Size scale;

  /// The linear index of the allocated texture slot.
  final int slotIndex;

  /// Creates a new [AtlasResult] instance.
  const AtlasResult({
    required this.offset,
    required this.scale,
    required this.slotIndex,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AtlasResult &&
          runtimeType == other.runtimeType &&
          offset == other.offset &&
          scale == other.scale &&
          slotIndex == other.slotIndex;

  @override
  int get hashCode => offset.hashCode ^ scale.hashCode ^ slotIndex.hashCode;

  @override
  String toString() =>
      'AtlasResult(offset: $offset, scale: $scale, slotIndex: $slotIndex)';
}

/// A GPU Texture Atlas Manager that manages a grid of texture slots using an LRU cache.
class TileAtlas {
  /// The number of horizontal slots in the grid.
  final int columns;

  /// The number of vertical slots in the grid.
  final int rows;

  /// The width of each slot in pixels.
  final int slotWidth;

  /// The height of each slot in pixels.
  final int slotHeight;

  // Track the images stored in slots. Supports standard ui.Image or custom mock images.
  final List<dynamic> _images;

  // Map of active tile ID -> slot index.
  final Map<String, int> _tileToSlot = {};

  // Map of slot index -> active tile ID.
  final Map<int, String> _slotToTile = {};

  // LRU tracking list of slot indices.
  // First element is the Least Recently Used (LRU), last is the Most Recently Used (MRU).
  final List<int> _lruList = [];

  // Stack/List of available slot indices.
  final List<int> _freeSlots = [];

  /// Creates a new [TileAtlas] instance.
  ///
  /// Defaults to a 16x16 grid with 256x256 pixel slots.
  TileAtlas({
    this.columns = 16,
    this.rows = 16,
    this.slotWidth = 256,
    this.slotHeight = 256,
  }) : _images = List<dynamic>.filled(columns * rows, null) {
    if (columns <= 0 || rows <= 0) {
      throw ArgumentError('Columns and rows must be greater than zero.');
    }
    // Populate free slots starting from the last index to 0.
    for (int i = (columns * rows) - 1; i >= 0; i--) {
      _freeSlots.add(i);
    }
  }

  /// The total capacity of the atlas (total number of slots).
  int get capacity => columns * rows;

  /// The number of currently occupied slots.
  int get size => _tileToSlot.length;

  /// Gets the slot offset and scale for a given tile ID.
  ///
  /// If the tile is already cached:
  /// - Marks it as most recently used.
  /// - Returns its existing UV offset and scale.
  ///
  /// If the tile is not cached:
  /// - Allocates a slot (either a free slot, or by evicting the least recently used tile).
  /// - If evicting, disposes of the evicted image if applicable.
  /// - Maps the tile to the allocated slot, marks it as most recently used, and returns the UV bounds.
  AtlasResult getOrCreateTile(String tileId) {
    if (_tileToSlot.containsKey(tileId)) {
      final slotIndex = _tileToSlot[tileId]!;
      _updateLru(slotIndex);
      return _makeResult(slotIndex);
    }

    int slotIndex;
    if (_freeSlots.isNotEmpty) {
      slotIndex = _freeSlots.removeLast();
    } else {
      if (_lruList.isEmpty) {
        throw StateError('Cannot evict a slot because the LRU tracking list is empty.');
      }
      // Evict the least recently used slot (index 0 in _lruList).
      slotIndex = _lruList.removeAt(0);
      final evictedTileId = _slotToTile[slotIndex];
      if (evictedTileId != null) {
        _tileToSlot.remove(evictedTileId);
        _slotToTile.remove(slotIndex);
      }

      // Safely dispose of the evicted image.
      final evictedImage = _images[slotIndex];
      if (evictedImage != null) {
        _disposeImage(evictedImage);
        _images[slotIndex] = null;
      }
    }

    _tileToSlot[tileId] = slotIndex;
    _slotToTile[slotIndex] = tileId;
    _lruList.add(slotIndex);

    return _makeResult(slotIndex);
  }

  /// Checks if a tile is currently cached in the atlas.
  bool contains(String tileId) => _tileToSlot.containsKey(tileId);

  /// Gets the slot index allocated to the tile ID, or `null` if not cached.
  ///
  /// Does NOT update the LRU status.
  int? getSlotIndex(String tileId) => _tileToSlot[tileId];

  /// Gets the image associated with the tile ID, or `null` if not cached or not set.
  ///
  /// Does NOT update the LRU status.
  dynamic getImageForTile(String tileId) {
    final slotIndex = _tileToSlot[tileId];
    if (slotIndex == null) return null;
    return _images[slotIndex];
  }

  /// Sets/associates an image with a tile ID.
  ///
  /// The tile must already have been allocated via [getOrCreateTile].
  /// If the slot already contained a different image, it is disposed of.
  void setImage(String tileId, dynamic image) {
    final slotIndex = _tileToSlot[tileId];
    if (slotIndex == null) {
      throw StateError('Cannot set image for non-allocated tile ID: $tileId');
    }

    final oldImage = _images[slotIndex];
    if (oldImage != null && oldImage != image) {
      _disposeImage(oldImage);
    }
    _images[slotIndex] = image;
  }

  /// Clears the atlas state and disposes of all cached images.
  void clear() {
    _tileToSlot.clear();
    _slotToTile.clear();
    _lruList.clear();
    _freeSlots.clear();

    for (int i = 0; i < _images.length; i++) {
      final img = _images[i];
      if (img != null) {
        _disposeImage(img);
        _images[i] = null;
      }
    }

    // Reset all slots to free slots (starting from last index down to 0).
    for (int i = (columns * rows) - 1; i >= 0; i--) {
      _freeSlots.add(i);
    }
  }

  void _updateLru(int slotIndex) {
    _lruList.remove(slotIndex);
    _lruList.add(slotIndex);
  }

  AtlasResult _makeResult(int slotIndex) {
    final col = slotIndex % columns;
    final row = slotIndex ~/ columns;
    final offset = ui.Offset(col / columns, row / rows);
    final scale = ui.Size(1.0 / columns, 1.0 / rows);
    return AtlasResult(
      offset: offset,
      scale: scale,
      slotIndex: slotIndex,
    );
  }

  void _disposeImage(dynamic image) {
    if (image is ui.Image) {
      image.dispose();
    } else {
      // For mock objects, check if they have a dispose method and call it.
      try {
        image.dispose();
      } catch (_) {
        // Ignore errors if the mock or custom object does not have a dispose method.
      }
    }
  }
}
