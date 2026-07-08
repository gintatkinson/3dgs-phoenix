import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:app_flutter/features/topology/topology_map.dart';

// TODO(#79): Replace mock topology data with dynamic DB-backed data.
// Currently used as fallback when widget.data is null.
// The data is loaded from assets/topology_data.json via loadTopologyData().

/// Empty topology data fallback used when real data is unavailable.
const emptyTopologyData = TopologyData(
  coordinateMapping: {},
  nodes: [],
  links: [],
);

TopologyData? _cachedTopologyData;

Map<String, dynamic> _parseJsonString(String jsonStr) {
  return jsonDecode(jsonStr) as Map<String, dynamic>;
}

/// Loads topology data from the external JSON asset.
Future<TopologyData> loadTopologyData() async {
  if (_cachedTopologyData != null) return _cachedTopologyData!;
  final jsonStr = await rootBundle.loadString('assets/topology_data.json');
  final Map<String, dynamic> data;
  if (kDebugMode) {
    data = _parseJsonString(jsonStr);
  } else {
    data = await compute(_parseJsonString, jsonStr);
  }
  _cachedTopologyData = TopologyData.fromJson(data);
  return _cachedTopologyData!;
}

/// Clears the topology data cache.
void clearTopologyCache() {
  _cachedTopologyData = null;
}
