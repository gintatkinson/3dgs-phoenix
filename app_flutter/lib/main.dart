import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:app_flutter/core/theme/theme_controller.dart';
import 'package:app_flutter/core/theme/text_scaler.dart';
import 'package:app_flutter/core/theme/theme_service.dart';
import 'package:app_flutter/domain/data_source.dart';
import 'package:app_flutter/domain/repository_resolver.dart';
import 'package:app_flutter/core/string_resources.dart';
import 'package:app_flutter/app/app.dart';
import 'package:app_flutter/domain/cesium_3d/scene_bootstrapper.dart';

// Benchmark access hooks — set after initialization
ThemeController? globalThemeController;
TextScalerController? globalTextScalerController;

const _dataSource = String.fromEnvironment('DATA_SOURCE', defaultValue: 'sqlite');

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  SceneBootstrapper.boot(args);
  final sceneId = SceneBootstrapper.sceneId;

  try {
    final isTest = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST') ||
        WidgetsBinding.instance.runtimeType.toString().contains('Test');
    final dataSource = await RepositoryResolver.resolve(
      dataSourceType: _dataSource,
      sqliteInMemory: isTest,
    );

    // Theme
    final themeService = SharedPreferencesThemeService();
    final themeController = ThemeController(themeService);
    await themeController.loadSettings();

    final textScalerController = TextScalerController(themeService);
    await textScalerController.load();

    globalThemeController = themeController;
    globalTextScalerController = textScalerController;

    await StringResources.load();

    runApp(
      MultiProvider(
        providers: [
          Provider<DataSource>.value(value: dataSource),
          ChangeNotifierProvider<ThemeController>.value(value: themeController),
          ChangeNotifierProvider<TextScalerController>.value(value: textScalerController),
        ],
        child: MyApp(sceneId: sceneId),
      ),
    );
  } catch (e, st) {
    debugPrint('FATAL ERROR in main(): $e\n$st');
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('Startup error:\n$e'),
          ),
        ),
      ),
    );
  }
}
