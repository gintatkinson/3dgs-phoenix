import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';
import 'package:app_flutter/core/app_config.dart';
import 'package:app_flutter/core/theme/app_themes.dart';
import 'package:app_flutter/core/theme/text_scaler.dart';
import 'package:app_flutter/core/theme/theme_controller.dart';
import 'package:app_flutter/features/layout/layout.dart';
import 'package:app_flutter/features/topology/scene_view_widget.dart';

class MyApp extends StatelessWidget {
  final String? sceneId;

  const MyApp({super.key, this.sceneId});

  @override
  Widget build(BuildContext context) {
    final themeController = context.watch<ThemeController>();
    final textScaler = context.watch<TextScalerController>();

    return MaterialApp(
      title: AppConfig.windowTitle,
      themeMode: themeController.themeMode,
      theme: AppThemes.light(custom: themeController.currentTheme),
      darkTheme: AppThemes.dark(custom: themeController.currentTheme),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScaler.scale),
          ),
          child: child!,
        );
      },
      home: sceneId != null ? SceneViewWidget(sceneId: sceneId!) : const DashboardPage(),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String _activeView = 'Master_1';
  late Future<String> _layoutConfigFuture;

  @override
  void initState() {
    super.initState();
    _layoutConfigFuture = rootBundle.loadString('assets/logical-layout.json');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _layoutConfigFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Text('Error loading layout configuration: ${snapshot.error}'),
            ),
          );
        }

        final layoutConfig = snapshot.data;

        return Layout(
          activeView: _activeView,
          onViewChange: (newView) {
            setState(() {
              _activeView = newView;
            });
          },
          layoutConfig: layoutConfig,
        );
      },
    );
  }
}
