import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:app_flutter/domain/data_sources/firebase_data_source.dart';

class DocUpdateEvent {
  final String collectionPath;
  final String docId;
  final Map<String, dynamic>? data;
  DocUpdateEvent(this.collectionPath, this.docId, this.data);
}

// Fake implementations of Firestore classes using noSuchMethod
class FakeFirebaseFirestore extends Fake implements FirebaseFirestore {
  final Map<String, Map<String, Map<String, dynamic>>> collections = {};
  final StreamController<DocUpdateEvent> _updateController = StreamController<DocUpdateEvent>.broadcast();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #collection) {
      final String path = invocation.positionalArguments.first as String;
      return FakeCollectionReference(this, path);
    }
    return super.noSuchMethod(invocation);
  }
}

class FakeCollectionReference extends Fake implements CollectionReference<Map<String, dynamic>> {
  final FakeFirebaseFirestore firestore;
  final String path;

  FakeCollectionReference(this.firestore, this.path);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #doc) {
      final String? id = invocation.positionalArguments.isNotEmpty 
          ? invocation.positionalArguments.first as String? 
          : null;
      final docId = id ?? 'auto_gen_id';
      return FakeDocumentReference(firestore, path, docId);
    }
    if (invocation.memberName == #where) {
      final field = invocation.positionalArguments.first;
      final isEqualTo = invocation.namedArguments[#isEqualTo];
      final isNull = invocation.namedArguments[#isNull];
      return FakeQuery(firestore, path)._where(
        field as Object,
        isEqualTo: isEqualTo,
        isNull: isNull as bool?,
      );
    }
    if (invocation.memberName == #limit) {
      final limitVal = invocation.positionalArguments.first as int;
      return FakeQuery(firestore, path)._limit(limitVal);
    }
    if (invocation.memberName == #get) {
      return FakeQuery(firestore, path).get();
    }
    return super.noSuchMethod(invocation);
  }
}

class FakeDocumentReference extends Fake implements DocumentReference<Map<String, dynamic>> {
  final FakeFirebaseFirestore firestore;
  final String collectionPath;
  final String docId;

  FakeDocumentReference(this.firestore, this.collectionPath, this.docId);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #id) {
      return docId;
    }
    if (invocation.memberName == #get) {
      final colData = firestore.collections[collectionPath] ?? {};
      final docData = colData[docId];
      return Future.value(FakeDocumentSnapshot(docId, docData));
    }
    if (invocation.memberName == #snapshots) {
      final controller = StreamController<DocumentSnapshot<Map<String, dynamic>>>();
      final initialColData = firestore.collections[collectionPath] ?? {};
      final initialDocData = initialColData[docId];
      controller.add(FakeDocumentSnapshot(docId, initialDocData));
      final subscription = firestore._updateController.stream.listen((event) {
        if (event.collectionPath == collectionPath && event.docId == docId) {
          controller.add(FakeDocumentSnapshot(docId, event.data));
        }
      });
      controller.onCancel = () {
        subscription.cancel();
        controller.close();
      };
      return controller.stream;
    }
    if (invocation.memberName == #set) {
      final data = invocation.positionalArguments[0] as Map<String, dynamic>;
      final options = invocation.positionalArguments.length > 1 
          ? invocation.positionalArguments[1] as SetOptions? 
          : null;
      final colData = firestore.collections.putIfAbsent(collectionPath, () => {});
      Map<String, dynamic> merged;
      if (options?.merge == true) {
        final existing = colData[docId] ?? {};
        merged = {...existing, ...data};
      } else {
        merged = Map<String, dynamic>.from(data);
      }
      colData[docId] = merged;
      firestore._updateController.add(DocUpdateEvent(collectionPath, docId, merged));
      return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

class FakeDocumentSnapshot extends Fake implements DocumentSnapshot<Map<String, dynamic>> {
  final String _id;
  final Map<String, dynamic>? _data;

  FakeDocumentSnapshot(this._id, this._data);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #id) {
      return _id;
    }
    if (invocation.memberName == #exists) {
      return _data != null;
    }
    if (invocation.memberName == #data) {
      return _data;
    }
    return super.noSuchMethod(invocation);
  }
}

class FakeQueryDocumentSnapshot extends Fake implements QueryDocumentSnapshot<Map<String, dynamic>> {
  final String _id;
  final Map<String, dynamic> _data;

  FakeQueryDocumentSnapshot(this._id, this._data);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #id) {
      return _id;
    }
    if (invocation.memberName == #data) {
      return _data;
    }
    return super.noSuchMethod(invocation);
  }
}

class FakeQuerySnapshot extends Fake implements QuerySnapshot<Map<String, dynamic>> {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs;

  FakeQuerySnapshot(this._docs);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #docs) {
      return _docs;
    }
    return super.noSuchMethod(invocation);
  }
}

class FakeQuery extends Fake implements Query<Map<String, dynamic>> {
  final FakeFirebaseFirestore firestore;
  final String collectionPath;
  final List<bool Function(String id, Map<String, dynamic> data)> filters;
  final int? _limitVal;

  FakeQuery(this.firestore, this.collectionPath, [this.filters = const [], this._limitVal]);

  FakeQuery _where(
    Object field, {
    Object? isEqualTo,
    bool? isNull,
  }) {
    final newFilters = List<bool Function(String id, Map<String, dynamic> data)>.from(filters);
    
    newFilters.add((id, data) {
      final key = field.toString();
      if (isNull != null) {
        final val = data[key];
        final matchesNull = (val == null);
        return isNull ? matchesNull : !matchesNull;
      }
      if (isEqualTo != null) {
        return data[key] == isEqualTo;
      }
      return true;
    });

    return FakeQuery(firestore, collectionPath, newFilters, _limitVal);
  }

  FakeQuery _limit(int limit) {
    return FakeQuery(firestore, collectionPath, filters, limit);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #where) {
      final field = invocation.positionalArguments.first;
      final isEqualTo = invocation.namedArguments[#isEqualTo];
      final isNull = invocation.namedArguments[#isNull];
      return _where(
        field as Object,
        isEqualTo: isEqualTo,
        isNull: isNull as bool?,
      );
    }
    if (invocation.memberName == #limit) {
      final limitVal = invocation.positionalArguments.first as int;
      return _limit(limitVal);
    }
    if (invocation.memberName == #get) {
      final colData = firestore.collections[collectionPath] ?? {};
      var docsList = colData.entries.map((e) => FakeQueryDocumentSnapshot(e.key, e.value)).toList();

      for (final filter in filters) {
        docsList = docsList.where((doc) => filter(doc.id, doc.data())).toList();
      }

      if (_limitVal != null && docsList.length > _limitVal!) {
        docsList = docsList.sublist(0, _limitVal!);
      }

      return Future.value(FakeQuerySnapshot(docsList));
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  group('FirebaseDataSource Tests', () {
    late FakeFirebaseFirestore mockFirestore;
    late FirebaseDataSource dataSource;

    setUp(() {
      mockFirestore = FakeFirebaseFirestore();
      dataSource = FirebaseDataSource(mockFirestore);

      // Seed standard schema
      mockFirestore.collections['schema'] = {
        'types': {
          'fields': {
            'Master_1': {
              'displayName': 'Master One',
              'childTypes': [
                {
                  'relationName': 'contains',
                  'childTypeName': 'RelationChild',
                  'childLabel': 'Relation Child Label'
                }
              ]
            },
            'Master_2': {
              'displayName': 'Master Two',
              'childTypes': []
            },
            'RelationChild': {
              'displayName': 'Relation Child Type',
            }
          }
        }
      };
    });

    test('fetchRootNodes retrieves root nodes and detects children correctly', () async {
      mockFirestore.collections['data'] = {
        'Master_2': {
          'type_name': 'Master_2',
          'parent_node_id': null,
        },
        'Master_1': {
          'type_name': 'Master_1',
          'parent_node_id': null,
          'name': 'Custom Master 1',
          'has_children': true,
        },
        'Child_Node': {
          'type_name': 'RelationChild',
          'parent_node_id': 'Master_1',
        }
      };

      final roots = await dataSource.fetchRootNodes();

      expect(roots.length, equals(2));
      
      // Sorted alphabetically by id: Master_1, then Master_2
      expect(roots[0].id, equals('Master_1'));
      expect(roots[0].label, equals('Custom Master 1'));
      expect(roots[0].children, isNotNull); // has children

      expect(roots[1].id, equals('Master_2'));
      expect(roots[1].label, equals('Master Two'));
      expect(roots[1].children, isNull); // no children
    });

    test('fetchChildrenForNode returns properties children and relation-based instances children', () async {
      mockFirestore.collections['data'] = {
        'Master_1': {
          'type_name': 'Master_1',
          'parent_node_id': null,
          'has_children': true,
        },
        // Direct child in properties (collection 'data')
        'Master_1_Child_1': {
          'type_name': 'RelationChild',
          'parent_node_id': 'Master_1',
          'name': 'Master 1 Child 1',
        },
      };

      // Instance child (in collection 'instances')
      mockFirestore.collections['instances'] = {
        'inst_RelationChild': {
          'parent_node_id': 'Master_1',
          'type_name': 'RelationChild',
        }
      };

      final children = await dataSource.fetchChildrenForNode('Master_1');

      // 'Master_1_Child_1' is a property child.
      // 'RelationChild' is also added because the type definition says Master_1 contains RelationChild,
      // and there is an instance of type 'RelationChild' under Master_1, and it's not already in properties list.
      expect(children.length, equals(2));

      // Sorted by custom logic: a.id.contains('_Child_') goes last.
      // So 'RelationChild' first, then 'Master_1_Child_1'.
      expect(children[0].id, equals('RelationChild'));
      expect(children[0].label, equals('Relation Child Label'));

      expect(children[1].id, equals('Master_1_Child_1'));
      expect(children[1].label, equals('Master 1 Child 1'));
    });

    test('fetchTopologyData parses geolocation nodes and link interfaces correctly', () async {
      mockFirestore.collections['data'] = {
        'Node_A': {
          'name': 'Node A',
          'has_location': true,
          'position': {
            'location': {
              'ellipsoid': {
                'latitude': '37.7749',
                'longitude': '-122.4194',
                'height': '10.0',
              }
            }
          }
        },
        'Node_B': {
          'name': 'Node B',
          'has_location': true,
          'ietfGeoLocation': {
            'ellipsoid': {
              'latitude': '34.0522',
              'longitude': '-118.2437',
            }
          }
        },
        'Node_No_Geo': {
          'name': 'No Geo',
        }
      };

      mockFirestore.collections['instances'] = {
        'interface_1': {
          'parent_node_id': 'Node_A',
          'type_name': 'interface',
          'description': 'link to node Node_B',
        },
        'non_interface': {
          'parent_node_id': 'Node_A',
          'type_name': 'other_type',
          'description': 'link to node Node_B',
        }
      };

      final topology = await dataSource.fetchTopologyData();

      expect(topology.nodes.length, equals(2));
      expect(topology.nodes[0].id, equals('Node_A'));
      expect(topology.nodes[0].label, equals('Node A'));
      expect(topology.nodes[0].position.dim0, equals(-122.4194));
      expect(topology.nodes[0].position.dim1, equals(37.7749));
      expect(topology.nodes[0].position.dim2, equals(10.0));

      expect(topology.nodes[1].id, equals('Node_B'));
      expect(topology.nodes[1].label, equals('Node B'));
      expect(topology.nodes[1].position.dim0, equals(-118.2437));
      expect(topology.nodes[1].position.dim1, equals(34.0522));
      expect(topology.nodes[1].position.dim2, equals(0.0));

      expect(topology.links.length, equals(1));
      expect(topology.links[0].source, equals('Node_A'));
      expect(topology.links[0].target, equals('Node_B'));
      expect(topology.links[0].type, equals('interface'));
    });

    test('discoverTypes caches schema descriptors locally', () async {
      final types1 = await dataSource.discoverTypes();
      expect(types1.length, equals(3));

      mockFirestore.collections['schema'] = {
        'types': <String, Map<String, dynamic>>{
          'fields': <String, dynamic>{}
        }
      };

      final types2 = await dataSource.discoverTypes();
      expect(types2.length, equals(3));

      final type = await dataSource.typeFor('Master_1');
      expect(type, isNotNull);
      expect(type!.displayName, equals('Master One'));
    });

    test('watchProperties yields updates when external changes are set', () async {
      final docId = 'test_node_stream';

      mockFirestore.collections['data'] = {
        docId: {'name': 'Initial Name', 'value': 42}
      };

      final stream = dataSource.watchProperties(docId);
      final list = <Map<String, dynamic>>[];
      final subscription = stream.listen((data) {
        list.add(data);
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(list.length, equals(1));
      expect(list.first['name'], equals('Initial Name'));

      final docRef = mockFirestore.collection('data').doc(docId);
      await docRef.set({'name': 'Updated Name', 'value': 100}, SetOptions(merge: true));

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(list.length, equals(2));
      expect(list[1]['name'], equals('Updated Name'));
      expect(list[1]['value'], equals(100));

      await subscription.cancel();
    });
  });
}
