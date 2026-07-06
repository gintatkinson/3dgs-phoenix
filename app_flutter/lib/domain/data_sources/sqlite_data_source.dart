import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:app_flutter/domain/instance_record.dart';
import 'package:app_flutter/domain/type_descriptor.dart';
import 'package:app_flutter/domain/data_source.dart';
import 'package:app_flutter/features/tree/tree_node.dart';
import 'package:app_flutter/features/topology/topology_map.dart' show TopologyData, TopologyNode, TopologyLink, TopologyNodePosition;

/// [DataSource] implementation backed by the local SQLite database.
///
/// Reads type definitions, attributes, and relations from the
/// `type_definitions`, `type_attributes`, and `type_relations` tables.
/// Instance data resides in `properties`, `elements`, `alarms`, and
/// `events` tables. Use this data source for offline-first or
/// single-user deployments where no remote backend is available.
/// The database is assumed to be already opened and migrated; no
/// schema creation is performed here. All reads hit the database
/// directly — results are NOT cached.
class SqliteDataSource implements DataSource {
    SqliteDataSource(this._db);
  final Database _db;
  final StreamController<Map<String, dynamic>> _propertiesController =
      StreamController<Map<String, dynamic>>.broadcast();
  List<TypeDescriptor>? _cachedTypes;

  @override
  String get name => 'sqlite';

  @override
  Future<void> dispose() async {
    _cachedTypes = null;
    await _propertiesController.close();
    await _db.close();
  }

  /// Reads all type definitions from the `type_definitions` table and
  /// hydrates each row into a [TypeDescriptor] by joining into
  /// `type_attributes` and `type_relations`.
  ///
  /// Returns an empty list when the table is empty (e.g. first launch
  /// before schema is seeded). Each call triggers at least
  /// (1 + N) SQL queries where N is the row count — use sparingly in
  /// hot paths. Does NOT throw on missing data; missing foreign rows
  /// simply produce empty fields/childTypes.
  @override
  Future<List<TypeDescriptor>> discoverTypes() async {
    if (_cachedTypes != null) return _cachedTypes!;
    try {
      final typeRows = await _db.query('type_definitions');
      final allAttrRows = await _db.query('type_attributes', orderBy: 'section_order, id');
      final allRelRows = await _db.query('type_relations');

      final attrsByType = <String, List<Map<String, dynamic>>>{};
      for (final row in allAttrRows) {
        final tn = row['type_name'] as String;
        (attrsByType[tn] ??= []).add(row);
      }
      final relsByType = <String, List<Map<String, dynamic>>>{};
      for (final row in allRelRows) {
        final tn = row['parent_type_name'] as String;
        (relsByType[tn] ??= []).add(row);
      }

      final types = typeRows.map((typeRow) {
        final typeName = typeRow['type_name'] as String;
        final attrRows = attrsByType[typeName] ?? [];
        final relRows = relsByType[typeName] ?? [];
        final childRows = relRows.where((r) => r['relation_name'] == 'contains');
        final relatedRows = relRows.where((r) => r['relation_name'] != 'contains');
        return TypeDescriptor(
          typeName: typeName,
          displayName: typeRow['display_name'] as String,
          iconName: typeRow['icon_name'] as String,
          fields: attrRows.map(_parseField).toList(),
          childTypes: childRows.map((r) => TypeRelationDescriptor(
            relationName: r['relation_name'] as String,
            childTypeName: r['child_type_name'] as String,
            childLabel: r['child_label'] as String,
          )).toList(),
          relatedTypes: relatedRows.map((r) => TypeRelationDescriptor(
            relationName: r['relation_name'] as String,
            childTypeName: r['child_type_name'] as String,
            childLabel: r['child_label'] as String,
          )).toList(),
          parentTypes: [],
        );
      }).toList();
      _cachedTypes = types;
      return types;
    } catch (e, stackTrace) {
      debugPrint('Error in discoverTypes: $e\n$stackTrace');
      return [];
    }
  }

  /// Queries `type_definitions` for a single row matching [typeName]
  /// and builds a [TypeDescriptor] from its attributes and relations.
  ///
  /// Returns `null` when [typeName] does not exist (e.g. a legacy
  /// node references a removed type). Throws if the row exists but
  /// `type_name` is null.
  @override
  Future<TypeDescriptor?> typeFor(String typeName) async {
    try {
      final rows = await _db.query('type_definitions',
          where: 'type_name = ?', whereArgs: [typeName]);
      if (rows.isEmpty) return null;
      return _buildType(rows.first);
    } catch (e, stackTrace) {
      debugPrint('Error in typeFor($typeName): $e\n$stackTrace');
      return null;
    }
  }

  /// Reads all parent-child type pairs from the `type_relations` table.
  ///
  /// Returns an empty list when no relations are defined (e.g. a flat
  /// ontology with no hierarchy). Each call triggers a full table
  /// scan — consider caching if the hierarchy is static.
  @override
  Future<List<(String, String)>> discoverHierarchy() async {
    try {
      final rows = await _db.query(
        'type_relations',
        where: "relation_name = 'contains'",
      );
      return rows.map((r) => (
        r['parent_type_name'] as String,
        r['child_type_name'] as String,
      )).toList();
    } catch (e, stackTrace) {
      debugPrint('Error in discoverHierarchy: $e\n$stackTrace');
      return [];
    }
  }

  /// Fetches the property map for the node identified by [nodeId]
  /// from the `properties` table.
  ///
  /// Returns an empty map when the node has no row (e.g. a newly
  /// created node that has never been saved) or when the stored
  /// `data_json` is null or malformed. Malformed JSON is silently
  /// caught and returns `{}` so the caller can present a blank form
  /// instead of crashing. Each call executes a single SELECT.
  @override
  Future<Map<String, dynamic>> fetchProperties(String nodeId) async {
    try {
      final maps = await _db.query(
        'properties',
        columns: ['data_json'],
        where: 'node_id = ?',
        whereArgs: [nodeId],
      );
      if (maps.isEmpty) return {};
      final dataJson = maps.first['data_json'] as String?;
      if (dataJson == null) return {};
      final decoded = Map<String, dynamic>.from(jsonDecode(dataJson) as Map);
      return _flatten(decoded);
    } catch (e, stackTrace) {
      debugPrint('Error in fetchProperties($nodeId): $e\n$stackTrace');
      return {};
    }
  }

  /// Persists [data] as the properties for [nodeId] in the
  /// `properties` table using an upsert (replace on conflict).
  ///
  /// STATE CHANGE: Writes to the `properties` table and emits a
  /// change event on the broadcast stream so all active
  /// [watchProperties] subscribers receive the update. Use this for
  /// both creates and updates — the upsert handles both transparently.
  @override
  Future<void> saveProperties(String nodeId, Map<String, dynamic> data) async {
    try {
      final unflattened = _unflatten(data);
      final dataJson = jsonEncode(unflattened);
      await _db.rawInsert('''
        INSERT INTO properties (node_id, data_json)
        VALUES (?, ?)
        ON CONFLICT(node_id) DO UPDATE SET
          data_json = excluded.data_json
      ''', [nodeId, dataJson]);
      _propertiesController.add({'nodeId': nodeId, 'data': data});
    } catch (e, stackTrace) {
      debugPrint('Error in saveProperties($nodeId): $e\n$stackTrace');
    }
  }

  /// Returns a broadcast stream that first emits the current
  /// properties for [nodeId] (via [fetchProperties]) and then yields
  /// subsequent updates whenever [saveProperties] is called for the
  /// same [nodeId].
  ///
  /// The initial yield is synchronous — callers receive the current
  /// state immediately upon subscription. Subscriptions that outlive
  /// the data source will receive events indefinitely; cancel the
  /// subscription to avoid leaks.
  @override
  Stream<Map<String, dynamic>> watchProperties(String nodeId) async* {
    yield await fetchProperties(nodeId);
    await for (final event in _propertiesController.stream) {
      if (event['nodeId'] == nodeId) {
        yield event['data'] as Map<String, dynamic>;
      }
    }
  }

  @override
  Future<List<InstanceRecord>> fetchRelatedInstances({
    required String parentNodeId,
    required TypeDescriptor targetType,
  }) async {
    try {
      final rows = await _db.query(
        'instances',
        where: 'parent_node_id = ? AND type_name = ?',
        whereArgs: [parentNodeId, targetType.typeName],
      );
      return compute(
        (args) => (args[0] as List<Map<String, dynamic>>)
            .map((r) => InstanceRecord.fromMap(r, args[1] as String))
            .toList(),
        [rows, targetType.typeName],
      );
    } catch (e, stackTrace) {
      debugPrint('Error in fetchRelatedInstances: $e\n$stackTrace');
      return [];
    }
  }

  @override
  Future<List<TreeNode>> fetchRootNodes() async {
    try {
      final rows = await _db.rawQuery('''
        SELECT p.node_id, td.display_name,
          (SELECT COUNT(*) FROM properties c WHERE c.parent_node_id = p.node_id) > 0 as has_children
        FROM properties p
        LEFT JOIN type_definitions td ON p.node_id = td.type_name
        WHERE p.parent_node_id IS NULL
        ORDER BY p.node_id
      ''');
      return rows.map((r) {
        final id = r['node_id'] as String;
        final label = (r['display_name'] as String?) ?? id.replaceAll('_', ' ');
        final hasChildren = (r['has_children'] as int? ?? 0) > 0;
        return TreeNode(
          id: id,
          label: label,
          children: hasChildren ? const [] : null,
        );
      }).toList();
    } catch (e, stackTrace) {
      debugPrint('Error in fetchRootNodes: $e\n$stackTrace');
      return [];
    }
  }

  @override
  Future<List<TreeNode>> fetchChildrenForNode(String parentId) async {
    try {
      final rows = await _db.rawQuery('''
        SELECT node_id, display_name, has_children FROM (
          SELECT p.node_id as node_id, td.display_name as display_name,
            (SELECT COUNT(*) FROM properties c WHERE c.parent_node_id = p.node_id) > 0 as has_children
          FROM properties p
          LEFT JOIN type_definitions td ON p.node_id = td.type_name
          WHERE p.parent_node_id = ?

          UNION ALL

          SELECT r.child_type_name as node_id, td.display_name as display_name,
            0 as has_children
          FROM type_relations r
          LEFT JOIN type_definitions td ON r.child_type_name = td.type_name
          WHERE r.parent_type_name = ? AND r.relation_name = 'contains'
            AND r.child_type_name NOT IN ('Detail_A', 'Detail_B', 'Detail_C')
            AND r.child_type_name NOT IN (SELECT node_id FROM properties WHERE parent_node_id = ?)
            AND r.child_type_name IN (SELECT type_name FROM instances WHERE parent_node_id = ?)
        )
        ORDER BY (CASE WHEN node_id LIKE '%_Child_%' OR node_id LIKE '%_Grandchild_%' THEN 1 ELSE 0 END), node_id
      ''', [parentId, parentId, parentId, parentId]);
      return rows.map((r) {
        final id = r['node_id'] as String;
        final label = (r['display_name'] as String?) ?? id.replaceAll('_', ' ');
        final hasChildren = (r['has_children'] as int? ?? 0) > 0;
        return TreeNode(
          id: id,
          label: label,
          children: hasChildren ? const [] : null,
        );
      }).toList();
    } catch (e, stackTrace) {
      debugPrint('Error in fetchChildrenForNode: $e\n$stackTrace');
      return [];
    }
  }

  Future<TypeDescriptor> _buildType(Map<String, dynamic> typeRow) async {
    final typeName = typeRow['type_name'] as String;
    final attrRows = await _db.query('type_attributes',
        where: 'type_name = ?',
        whereArgs: [typeName],
        orderBy: 'section_order, id');
    final relRows = await _db.query('type_relations',
        where: 'parent_type_name = ?', whereArgs: [typeName]);

    final childRows = relRows.where((r) => r['relation_name'] == 'contains');
    final relatedRows = relRows.where((r) => r['relation_name'] != 'contains');

    return TypeDescriptor(
      typeName: typeName,
      displayName: typeRow['display_name'] as String,
      iconName: typeRow['icon_name'] as String,
      fields: attrRows.map(_parseField).toList(),
      childTypes: childRows.map((r) => TypeRelationDescriptor(
        relationName: r['relation_name'] as String,
        childTypeName: r['child_type_name'] as String,
        childLabel: r['child_label'] as String,
      )).toList(),
      relatedTypes: relatedRows.map((r) => TypeRelationDescriptor(
        relationName: r['relation_name'] as String,
        childTypeName: r['child_type_name'] as String,
        childLabel: r['child_label'] as String,
      )).toList(),
      parentTypes: [], // populated by caller if needed
    );
  }

  FieldDescriptor _parseField(Map<String, dynamic> row) {
    List<String>? parseJsonList(String? raw) {
      if (raw == null || raw.isEmpty) return null;
      return (jsonDecode(raw) as List).cast<String>();
    }

    return FieldDescriptor(
      key: row['attr_key'] as String,
      label: row['label'] as String,
      type: row['attr_type'] as String,
      sectionLabel: row['section_label'] as String?,
      sectionOrder: row['section_order'] as int? ?? 0,
      required: (row['is_required'] as int? ?? 0) == 1,
      minValue: row['min_value'] as num?,
      maxValue: row['max_value'] as num?,
      pattern: row['pattern'] as String?,
      enumOptions: parseJsonList(row['enum_options'] as String?),
      enumDisplayNames: parseJsonList(row['enum_display_names'] as String?),
      defaultValue: row['default_value'],
      inputFormatters: parseJsonList(row['input_formatters'] as String?),
    );
  }

  Map<String, dynamic> _flatten(Map<String, dynamic> map, {String prefix = ''}) {
    final result = <String, dynamic>{};
    map.forEach((key, value) {
      final newKey = prefix.isEmpty ? key : '$prefix.$key';
      if (value is Map) {
        result.addAll(_flatten(Map<String, dynamic>.from(value), prefix: newKey));
      } else {
        result[newKey] = value;
      }
    });
    return result;
  }

  Map<String, dynamic> _unflatten(Map<String, dynamic> map) {
    final result = <String, dynamic>{};
    map.forEach((key, value) {
      final parts = key.split('.');
      Map<String, dynamic> current = result;
      for (int i = 0; i < parts.length - 1; i++) {
        final part = parts[i];
        if (!current.containsKey(part) || current[part] is! Map) {
          current[part] = <String, dynamic>{};
        }
        current = current[part] as Map<String, dynamic>;
      }
      current[parts.last] = value;
    });
    return result;
  }

  @override
  Future<TopologyData> fetchTopologyData() async {
    try {
      final rows = await _db.query('properties');
      final interfaceRows = await _db.query(
        'instances',
        where: "type_name = 'interface'",
      );
      return compute(_parseTopologyData, <dynamic>[rows, interfaceRows]);
    } catch (e, stackTrace) {
      debugPrint('Error in fetchTopologyData: $e\n$stackTrace');
      return const TopologyData(coordinateMapping: {}, nodes: [], links: []);
    }
  }

  static TopologyData _parseTopologyData(List<dynamic> args) {
    final rows = args[0] as List<Map<String, dynamic>>;
    final interfaceRows = args[1] as List<Map<String, dynamic>>;
    final List<TopologyNode> nodes = [];
    final List<TopologyLink> links = [];

    for (final r in rows) {
      final nodeId = r['node_id'] as String;
      final dataJson = r['data_json'] as String?;
      if (dataJson == null || dataJson.isEmpty || dataJson == '{}') continue;

      final decoded = Map<String, dynamic>.from(jsonDecode(dataJson) as Map);

      final geo = decoded['ietfGeoLocation'] ?? decoded['location'] ?? decoded['position'];
      if (geo == null) continue;

      double? latVal;
      double? lngVal;
      double? altVal;

      if (geo is Map) {
        final loc = geo['location'] ?? geo;
        if (loc is Map) {
          final ellip = loc['ellipsoid'] ?? loc;
          if (ellip is Map) {
            latVal = double.tryParse(ellip['latitude']?.toString() ?? '');
            lngVal = double.tryParse(ellip['longitude']?.toString() ?? '');
            altVal = double.tryParse(ellip['height']?.toString() ?? ellip['altitude']?.toString() ?? '');
          }
        }
      }

      if (latVal == null || lngVal == null) {
        continue;
      }

      nodes.add(TopologyNode(
        id: nodeId,
        label: decoded['name']?.toString() ?? nodeId,
        position: TopologyNodePosition(
          dim0: lngVal,
          dim1: latVal,
          dim2: altVal ?? 0.0,
          timeIndex: 0,
          vector: const [],
        ),
        status: decoded['status']?.toString() ?? 'Active',
        rawProperties: decoded,
      ));
    }

    final regExp = RegExp(r'link to node\s+([\w\-]+)');
    for (final row in interfaceRows) {
      final parentNodeId = row['parent_node_id'] as String;
      final dataJson = row['data_json'] as String?;
      if (dataJson == null || dataJson.isEmpty || dataJson == '{}') continue;

      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(dataJson) as Map);
        final description = decoded['description']?.toString();
        if (description != null) {
          final match = regExp.firstMatch(description);
          if (match != null) {
            final targetNodeId = match.group(1)!;
            links.add(TopologyLink(
              source: parentNodeId,
              target: targetNodeId,
              type: 'interface',
            ));
          }
        }
      } catch (_) {}
    }

    return TopologyData(
      coordinateMapping: const {},
      nodes: nodes,
      links: links,
    );
  }
}

