import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:app_flutter/core/theme/theme_controller.dart';
import 'package:app_flutter/core/theme/widgets/settings_panel.dart';
import 'package:app_flutter/core/string_resources.dart';
import 'package:app_flutter/features/tree/tree_node_widget.dart';
import 'package:app_flutter/features/tree/view_models/tree_view_model.dart';

class SidebarTree extends StatefulWidget {
  final int? workerResult;
  final ValueChanged<String> onViewSelected;
  final EdgeInsetsGeometry contentPadding;

  const SidebarTree({
    super.key,
    this.workerResult,
    required this.onViewSelected,
    this.contentPadding = const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
  });

  @override
  State<SidebarTree> createState() => _SidebarTreeState();
}

class _SidebarTreeState extends State<SidebarTree> {
  bool _openingSettings = false;

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<TreeViewModel>();
    final treeData = viewModel.treeData;
    final brandPrimary = Theme.of(context).colorScheme.primary;
    final panelOpacity = context.watch<ThemeController>().panelOpacity;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withOpacity(panelOpacity),
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.developer_board,
                  color: brandPrimary,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    StringResources.get('sidebar.header'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Focus(
              focusNode: viewModel.focusNode,
              onKeyEvent: (FocusNode node, KeyEvent event) {
                if (event is KeyDownEvent) {
                  final key = event.logicalKey;
                  if (key == LogicalKeyboardKey.arrowDown) {
                    viewModel.moveFocusDown();
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.arrowUp) {
                    viewModel.moveFocusUp();
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) {
                    final currentId = viewModel.currentView;
                    if (currentId != null) {
                      viewModel.selectView(currentId);
                    }
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: SingleChildScrollView(
                padding: widget.contentPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: treeData.map((node) => TreeNodeWidget(
                    node: node,
                  )).toList(),
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              border: Border(
                top: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.tertiary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Worker: ${widget.workerResult ?? "Idle"}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                IconButton(
                  key: const Key('sidebar_settings_button'),
                  icon: const Icon(Icons.settings, size: 18),
                  onPressed: _openingSettings ? null : () {
                    setState(() => _openingSettings = true);
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (context) => const SettingsPanel(),
                    ).whenComplete(() {
                      if (mounted) setState(() => _openingSettings = false);
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
