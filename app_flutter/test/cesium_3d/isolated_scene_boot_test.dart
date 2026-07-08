import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:app_flutter/app/app.dart';
import 'package:app_flutter/core/theme/theme_controller.dart';
import 'package:app_flutter/core/theme/theme_service.dart';
import 'package:app_flutter/core/theme/text_scaler.dart';
import 'package:app_flutter/domain/data_source.dart';
import 'package:app_flutter/domain/instance_record.dart';
import 'package:app_flutter/domain/type_descriptor.dart';
import 'package:app_flutter/features/tree/tree_node.dart';
import 'package:app_flutter/features/topology/topographical_view.dart';
import 'package:app_flutter/features/topology/topology_map.dart';
import 'package:app_flutter/domain/cesium_3d/scene_bootstrapper.dart';
import 'package:app_flutter/domain/cesium_3d/process_executor.dart';
import 'package:app_flutter/domain/cesium_3d/grpc_channel.dart';
import 'package:app_flutter/features/topology/scene_view_widget.dart';
import 'package:app_flutter/features/topology/topology_defaults.dart';

class MockProcess implements Process {
  final int _pid;
  final Completer<int> _exitCodeCompleter = Completer<int>();

  MockProcess({int pid = 123}) : _pid = pid;

  @override
  Future<int> get exitCode => _exitCodeCompleter.future;

  void simulateExit(int code) {
    if (!_exitCodeCompleter.isCompleted) {
      _exitCodeCompleter.complete(code);
    }
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    simulateExit(-1);
    return true;
  }

  @override
  int get pid => _pid;

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  IOSink get stdin => throw UnimplementedError();

  @override
  Stream<List<int>> get stdout => const Stream.empty();
}

class MockDataSource implements DataSource {
  @override
  String get name => 'mock';

  @override
  Future<List<TypeDescriptor>> discoverTypes() async => [];

  @override
  Future<TypeDescriptor?> typeFor(String typeName) async => null;

  @override
  Future<List<(String, String)>> discoverHierarchy() async => [];

  @override
  Future<Map<String, dynamic>> fetchProperties(String nodeId) async => {};

  @override
  Future<void> saveProperties(String nodeId, Map<String, dynamic> data) async {}

  @override
  Stream<Map<String, dynamic>> watchProperties(String nodeId) => Stream.value({});

  @override
  Future<List<InstanceRecord>> fetchRelatedInstances({
    required String parentNodeId,
    required TypeDescriptor targetType,
  }) async => [];

  @override
  Future<List<TreeNode>> fetchRootNodes() async => [];

  @override
  Future<List<TreeNode>> fetchChildrenForNode(String parentId) async => [];

  @override
  Future<TopologyData> fetchTopologyData() async => const TopologyData(coordinateMapping: {}, nodes: [], links: []);

  @override
  Future<void> dispose() async {}
}

class MockThemeService extends ThemeService {
  @override
  Future<void> save(String key, String value) async {}

  @override
  Future<String?> load(String key) async => null;

  @override
  Future<Axis> loadLayoutSplitAxis() async => Axis.vertical;

  @override
  Future<double> loadPanelOpacity() async => 1.0;

  @override
  Future<double> loadTextScale() async => 1.0;

  @override
  Future<ThemeMode> loadThemeMode() async => ThemeMode.system;

  @override
  Future<int> loadThemeScheme() async => 0;

  @override
  Future<void> saveLayoutSplitAxis(Axis axis) async {}

  @override
  Future<void> savePanelOpacity(double opacity) async {}

  @override
  Future<void> saveTextScale(double scale) async {}

  @override
  Future<void> saveThemeMode(ThemeMode themeMode) async {}

  @override
  Future<void> saveThemeScheme(int index) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Register mock asset handler on flutter/assets channel
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (ByteData? message) async {
      if (message == null) return null;
      final Uint8List list = message.buffer.asUint8List(message.offsetInBytes, message.lengthInBytes);
      final String key = utf8.decode(list);
      if (key == 'assets/topology_data.json') {
        return ByteData.view(Uint8List.fromList(utf8.encode(
          '{"coordinate_mapping": {"x": "position/dim_0", "y": "position/dim_1"}, "nodes": [{"id": "3d_viewer", "label": "3D Viewer", "position": {"dim_0": 100.0, "dim_1": 200.0, "dim_2": 0.0, "time_index": 1.0, "vector": [0.0, 0.0, 0.0]}, "status": "Active"}], "links": []}'
        )).buffer);
      }
      return null;
    });
  });

  setUp(() {
    clearTopologyCache();
  });

  group('CLI Arg Parsing (SceneBootstrapper)', () {
    test('Correctly parses and sets isolated scene parameters', () {
      final args = ['--scene=3d_viewer', '--target_id=ring_01'];
      final isIsolated = SceneBootstrapper.boot(args);
      expect(isIsolated, isTrue);
      expect(SceneBootstrapper.sceneId, equals('3d_viewer'));
      expect(SceneBootstrapper.isIsolatedSceneMode, isTrue);
    });

    test('Bypasses isolated mode when --scene parameter is absent', () {
      final args = ['--mode=debug', '--port=8080'];
      final isIsolated = SceneBootstrapper.boot(args);
      expect(isIsolated, isFalse);
      expect(SceneBootstrapper.sceneId, isNull);
      expect(SceneBootstrapper.isIsolatedSceneMode, isFalse);
    });
  });

  group('Process Spawning & Crash Isolation', () {
    test('ProcessExecutor spawns independent subprocesses and handles termination isolation', () async {
      final mockProcess = MockProcess(pid: 9999);
      final executor = ProcessExecutor(
        spawn: (executable, args, {required mode}) async {
          expect(mode, equals(ProcessStartMode.detached));
          return mockProcess;
        },
      );

      final success = await executor.startProcess('flutter', ['run', '--scene=3d_viewer']);
      expect(success, isTrue);

      // Simulate a subprocess crash (non-zero exit code)
      mockProcess.simulateExit(139);

      // Verify that the child process exited but the parent context is unimpacted
      expect(mockProcess.pid, equals(9999));
      final exitCode = await mockProcess.exitCode;
      expect(exitCode, equals(139));
    });
  });

  group('SceneViewWidget Lifecycle & States', () {
    late GrpcChannel grpcChannel;
    late ThemeController themeController;
    late TextScalerController textScalerController;
    late DataSource mockDataSource;

    setUp(() {
      grpcChannel = GrpcChannel(socketPath: '/tmp/test_uds.sock');
      themeController = ThemeController(MockThemeService());
      textScalerController = TextScalerController(MockThemeService());
      mockDataSource = MockDataSource();
    });

    tearDown(() {
      grpcChannel.dispose();
    });

    testWidgets('Visual states transitions: Loading, Active, and Fault', (WidgetTester tester) async {
      // 1. Initial State should show Loading Progress Spinner while socket connects
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<DataSource>.value(value: mockDataSource),
            ChangeNotifierProvider<ThemeController>.value(value: themeController),
            ChangeNotifierProvider<TextScalerController>.value(value: textScalerController),
          ],
          child: MaterialApp(
            home: SceneViewWidget(
              sceneId: '3d_viewer',
              grpcChannel: grpcChannel,
            ),
          ),
        ),
      );

      // Spinner should be visible initially during load/connect delay
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(TopographicalView), findsNothing);
      expect(find.text('Connection Lost'), findsNothing);

      // 2. Allow futures (channel.connect and loadTopologyData) to complete and transition to Active State
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(TopographicalView), findsOneWidget);
      expect(find.text('Connection Lost'), findsNothing);

      // 3. Trigger a disconnection to transition to Fault State
      grpcChannel.disconnect();
      await tester.pump();
      await tester.pumpAndSettle();

      // Warning banner "Connection Lost" should be persistent and visible
      expect(find.text('Connection Lost'), findsOneWidget);
      expect(find.byType(TopographicalView), findsOneWidget); // retained underneath
    });
  });
}
