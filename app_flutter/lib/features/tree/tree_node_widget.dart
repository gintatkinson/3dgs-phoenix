import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:app_flutter/features/tree/tree_node.dart';
import 'package:app_flutter/features/tree/view_models/tree_view_model.dart';

/// Renders a single [TreeNode] row in the sidebar tree with expand/collapse
/// and selection highlighting.
///
/// Recursively renders child nodes indented under their parent when expanded.
/// Selection state is read from [TreeViewModel.currentView]; expansion state
/// from [TreeViewModel.expanded]. Tapping a leaf node calls
/// [TreeViewModel.selectView], while parent nodes show a toggle handle to
/// expand/collapse children.
///
/// [childIndent] controls the left indentation applied to child nodes.
///
/// Edge cases: root-level nodes with no parent; nodes whose parent is
/// collapsed are not rendered on screen (filtered by [TreeViewModel]'s
/// visible-node walk). Does not trigger [notifyListeners] directly — all
/// state changes are delegated to the view model.
class TreeNodeWidget extends StatelessWidget {
  final TreeNode node;
  /// The left indentation for child nodes in the tree.
  ///
  /// Applied as [EdgeInsets.only(left: childIndent)] to the [Padding] that
  /// wraps recursively rendered children. Defaults to 16.0.
  final double childIndent;

  const TreeNodeWidget({
    super.key,
    required this.node,
    this.childIndent = 16.0,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = context.select<TreeViewModel, bool>(
      (vm) => vm.currentView == node.id,
    );
    final isExpanded = context.select<TreeViewModel, bool>(
      (vm) => vm.expanded[node.id] == true,
    );
    final isLoading = context.select<TreeViewModel, bool>(
      (vm) => vm.loadingNodes[node.id] == true,
    );
    final nodeKeyValue = context.select<TreeViewModel, GlobalKey?>(
      (vm) => vm.nodeKey(node.id),
    );
    final isParent = node.children != null;

    IconData icon;
    if (isParent) {
      icon = isExpanded ? Icons.folder_open : Icons.folder;
    } else {
      icon = Icons.insert_drive_file;
    }

    final brandPrimary = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          key: nodeKeyValue,
          type: MaterialType.transparency,
          child: Ink(
            color: isSelected ? brandPrimary.withValues(alpha: 0.12) : null,
            child: InkWell(
              key: Key('node_${node.id}'),
              onTap: isLoading ? null : () {
                final viewModel = context.read<TreeViewModel>();
                viewModel.selectView(node.id);
                viewModel.focusNode.requestFocus();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      size: 16,
                      color: isSelected
                          ? brandPrimary
                          : Theme.of(context).iconTheme.color?.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        node.label,
                        style: Theme.of(context).textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isParent) ...[
                      const SizedBox(width: 4),
                      isLoading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                              ),
                            )
                          : InkWell(
                              key: Key('toggle_${node.id}'),
                              onTap: () {
                                context.read<TreeViewModel>().toggleExpand(node.id);
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(2.0),
                                child: Text(
                                  isExpanded ? '−' : '+',
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                              ),
                            ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        if (isParent && isExpanded && !isLoading)
          Padding(
            padding: EdgeInsets.only(left: childIndent),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: node.children!.map((child) => TreeNodeWidget(
                node: child,
              )).toList(),
            ),
          ),
      ],
    );
  }
}
