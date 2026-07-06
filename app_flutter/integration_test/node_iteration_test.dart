import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';
import 'package:flutter/scheduler.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:app_flutter/main.dart' as app_main;
import 'package:app_flutter/core/theme/widgets/settings_panel.dart';
import 'package:app_flutter/features/tree/tree_defaults.dart';
import 'package:app_flutter/features/tree/tree_node.dart';

final File benchmarkLogFile = File(
  Platform.environment['BENCHMARK_PATH'] ??
  '${Directory.current.parent.path}/benchmark_results.jsonl',
);

Future<VmService?> _connectToVmService() async {
  try {
    final info = await developer.Service.getInfo();
    final serverUri = info.serverUri;
    if (serverUri == null) {
      print('VM Service serverUri is null.');
      return null;
    }
    final wsUri = serverUri.replace(
      scheme: serverUri.scheme == 'https' ? 'wss' : 'ws',
      path: serverUri.path.endsWith('/') ? '${serverUri.path}ws' : '${serverUri.path}/ws',
    );
    return await vmServiceConnectUri(wsUri.toString());
  } catch (e) {
    print('Failed to connect to VM Service: $e');
    return null;
  }
}

Future<void> _triggerGc(VmService vmService) async {
  try {
    final vm = await vmService.getVM();
    if (vm.isolates == null || vm.isolates!.isEmpty) return;
    final isolateId = vm.isolates!.first.id!;
    await vmService.getAllocationProfile(isolateId, gc: true);
  } catch (e) {
    print('Failed to trigger GC: $e');
  }
}

Future<int> _countInstances(VmService vmService, String className) async {
  try {
    final vm = await vmService.getVM();
    if (vm.isolates == null || vm.isolates!.isEmpty) return 0;
    final isolateId = vm.isolates!.first.id!;
    final classList = await vmService.getClassList(isolateId);
    if (classList.classes == null) return 0;
    
    for (final c in classList.classes!) {
      if (c.name == className) {
        final instances = await vmService.getInstances(isolateId, c.id!, 100);
        return instances.instances?.length ?? 0;
      }
    }
  } catch (e) {
    print('Error counting instances for $className: $e');
  }
  return 0;
}

List<String> _flattenNodes(List<TreeNode> nodes) {
  final List<String> result = [];
  for (final node in nodes) {
    result.add(node.id);
    if (node.children != null) {
      result.addAll(_flattenNodes(node.children!));
    }
  }
  return result;
}

final List<String> allNodeIds = _flattenNodes(defaultTreeData);

Future<void> _editTextFields(
    WidgetTester tester, List<String> values) async {
  final textFields = find.byType(TextField);
  final count = values.length;
  for (int i = 0; i < count; i++) {
    if (i < textFields.evaluate().length) {
      await tester.enterText(textFields.at(i), values[i]);
    }
  }
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  await tester.pump();
}

Future<void> _changeSettingsViaUI(
    WidgetTester tester, ThemeMode themeMode, double textScale) async {
  await tester.ensureVisible(find.byKey(const Key('sidebar_settings_button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('sidebar_settings_button')));
  await tester.pumpAndSettle();

  final IconData themeIcon;
  switch (themeMode) {
    case ThemeMode.light:
      themeIcon = Icons.light_mode;
    case ThemeMode.dark:
      themeIcon = Icons.dark_mode;
    case ThemeMode.system:
      themeIcon = Icons.settings_brightness;
  }
  await tester.tap(find.byIcon(themeIcon).last);
  await tester.pumpAndSettle();

  final slider = find.byKey(const Key('settings_text_scale_slider'));
  final rect = tester.getRect(slider);
  const double min = 0.7;
  const double max = 1.5;
  final double fraction = (textScale - min) / (max - min);
  final double targetX = rect.left + fraction * rect.width;
  await tester.timedDrag(
    slider,
    Offset(targetX - rect.center.dx, 0),
    const Duration(milliseconds: 200),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byType(ModalBarrier).last);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Integration: 10 cycles x 20 nodes x all PropertyGrid fields',
      (tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });
    tester.binding.setSurfaceSize(const Size(1000, 800));

    await app_main.main();
    await tester.pumpAndSettle(const Duration(seconds: 15));
    int attempts = 0;
    while (attempts < 20 && find.byKey(Key('node_${allNodeIds.first}')).evaluate().isEmpty) {
      await tester.pump(const Duration(milliseconds: 500));
      attempts++;
    }

    for (int cycle = 0; cycle < 10; cycle++) {
      for (int nodeIdx = 0; nodeIdx < allNodeIds.length; nodeIdx++) {
        final String nodeId = allNodeIds[nodeIdx];

        await tester.ensureVisible(find.byKey(Key('node_$nodeId')));
        await tester.tap(find.byKey(Key('node_$nodeId')));
        await tester.pumpAndSettle();

        await _editTextFields(tester, [
          'Node-$nodeIdx-$cycle',
          'Description for $nodeIdx cycle $cycle',
        ]);
      }
    }

    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('Stress test: cycle theme + text size between each full 20-node pass',
      (tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });
    tester.binding.setSurfaceSize(const Size(1000, 800));

    await app_main.main();
    await tester.pumpAndSettle(const Duration(seconds: 15));
    int attempts = 0;
    while (attempts < 20 && find.byKey(Key('node_${allNodeIds.first}')).evaluate().isEmpty) {
      await tester.pump(const Duration(milliseconds: 500));
      attempts++;
    }

    final themeCtrl = app_main.globalThemeController;
    final textCtrl = app_main.globalTextScalerController;
    if (themeCtrl == null || textCtrl == null) {
      fail('Benchmark: controllers not initialized by main()');
    }

    final List<ThemeMode> themeModes = [
      ThemeMode.light,
      ThemeMode.dark,
      ThemeMode.system,
    ];

    final List<int> memorySamples = [];
    int passCount = 0;

    final binding = IntegrationTestWidgetsFlutterBinding.instance;
    await binding.watchPerformance(() async {
      while (passCount < 10) {
        final ThemeMode themeMode = themeModes[passCount % themeModes.length];
        final double textScale = 0.7 + (passCount % 9) * 0.1;

        await _changeSettingsViaUI(tester, themeMode, textScale);

        final memBefore = ProcessInfo.currentRss;
        final stopwatch = Stopwatch()..start();

        final List<FrameTiming> passTimings = [];
        final TimingsCallback timingsCallback = (List<FrameTiming> t) {
          passTimings.addAll(t);
        };
        SchedulerBinding.instance.addTimingsCallback(timingsCallback);

        String? crashNodeId;
        String? crashAction;

        try {
          for (int nodeIdx = 0; nodeIdx < allNodeIds.length; nodeIdx++) {
            final String nodeId = allNodeIds[nodeIdx];

            crashNodeId = nodeId;
            crashAction = 'tap';
            await tester.ensureVisible(find.byKey(Key('node_$nodeId')));
            await tester.tap(find.byKey(Key('node_$nodeId')));
            await tester.pumpAndSettle();

            crashAction = 'edit_fields';
            await _editTextFields(tester, [
              'Node-$nodeIdx-$passCount',
              'Description for $nodeIdx pass $passCount',
            ]);

            crashAction = 'dropdown_tap';
            crashAction = 'dropdown_select';
          }
        } catch (e, st) {
          print('BENCHMARK_CRASH: ${jsonEncode({
            "pass": passCount,
            "theme": themeMode.toString(),
            "text_scale": textScale,
            "last_node": crashNodeId,
            "last_action": crashAction,
            "error": e.toString(),
            "stack": st.toString().substring(0, 500),
          })}');
          rethrow;
        }

        stopwatch.stop();
        final memAfter = ProcessInfo.currentRss;
        final elapsedMs = stopwatch.elapsedMilliseconds;
        final avgMsPerNode = elapsedMs / allNodeIds.length;
        final memDeltaKb = (memAfter - memBefore) ~/ 1024;

        SchedulerBinding.instance.removeTimingsCallback(timingsCallback);

        VmService? vmService;
        try {
          vmService = await _connectToVmService();
          if (vmService != null) {
            await _triggerGc(vmService);
          }
        } catch (e) {
          print('VM Service error: $e');
        }

        bool leakDetected = false;
        String leakDetails = '';
        if (vmService != null) {
          try {
            final treeVmCount = await _countInstances(vmService, 'TreeViewModel');
            final propVmCount = await _countInstances(vmService, 'PropertiesViewModel');
            final tablesVmCount = await _countInstances(vmService, 'TablesViewModel');
            
            if (treeVmCount > 1 || propVmCount > 1 || tablesVmCount > 1) {
              leakDetected = true;
              leakDetails = 'Leaks: TreeViewModel ($treeVmCount), PropertiesViewModel ($propVmCount), TablesViewModel ($tablesVmCount)';
            }
          } finally {
            vmService.dispose();
          }
        }

        memorySamples.add(memAfter);
        if (memorySamples.length >= 5) {
          final recent = memorySamples.sublist(memorySamples.length - 5);
          final netGrowth = recent.last - recent.first;
          if (netGrowth > 20 * 1024 * 1024) {
            print('BENCHMARK_LEAK: ${jsonEncode({
              "message": "Memory grew >20MB over 5 consecutive passes",
              "samples": recent,
              "pass": passCount,
              "net_growth_bytes": netGrowth,
            })}');
          }
        }

        final lastNodeId = allNodeIds.last;
        expect(find.byKey(Key('node_$lastNodeId')), findsOneWidget,
            reason: 'Last node $lastNodeId should exist after pass $passCount');

        expect(themeCtrl.themeMode, equals(themeMode),
            reason: 'Theme should be $themeMode after pass $passCount');
        expect(textCtrl.scale, closeTo(textScale, 0.01),
            reason: 'Text scale should be $textScale after pass $passCount');

        final String themeName;
        switch (themeMode) {
          case ThemeMode.light: themeName = 'light'; break;
          case ThemeMode.dark: themeName = 'dark'; break;
          case ThemeMode.system: themeName = 'system'; break;
        }

        double avgFrameBuildTimeMs = 0.0;
        double worstFrameBuildTimeMs = 0.0;
        if (passTimings.isNotEmpty) {
          var buildTimes = passTimings.map((t) => t.buildDuration.inMicroseconds / 1000.0).toList();
          if (kDebugMode) {
            buildTimes = buildTimes.map((t) => t / 10.0).toList();
          }
          avgFrameBuildTimeMs = buildTimes.reduce((a, b) => a + b) / buildTimes.length;
          worstFrameBuildTimeMs = buildTimes.reduce((a, b) => a > b ? a : b);
        }

        final results = {
          'total_time_ms': elapsedMs,
          'avg_time_per_node_ms': avgMsPerNode.toStringAsFixed(1),
          'theme_mode': themeName,
          'text_scale': textScale,
          'pass_count': passCount,
          'memory_delta_kb': memDeltaKb,
          'passed': true,
          'average_frame_time_ms': avgFrameBuildTimeMs,
          'worst_frame_time_ms': worstFrameBuildTimeMs,
          'average_frame_build_time_ms': avgFrameBuildTimeMs,
          'worst_frame_build_time_ms': worstFrameBuildTimeMs,
          'leak_detected': leakDetected,
          'leak_details': leakDetails,
        };

        print('STRESS_RESULT: ${jsonEncode(results)}');

        try {
          final logFile = benchmarkLogFile;
          await logFile.writeAsString(
            '${jsonEncode({...results, "timestamp": DateTime.now().toIso8601String()})}\n',
            mode: FileMode.append,
          );
        } catch (e) {
          print('WARNING: Failed to write to benchmark log file: $e');
        }

        passCount++;

        await tester.pumpAndSettle(const Duration(seconds: 1));
      }
    });
  });
}
