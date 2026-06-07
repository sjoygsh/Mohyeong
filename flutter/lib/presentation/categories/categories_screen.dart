import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/category/category_repository.dart';
import '../../domain/category/model/category.dart';

/// Manage the user-defined library categories. The implicit system
/// category (id=0, "Uncategorized") is hidden -- the SQL trigger blocks
/// deleting it and the Kotlin app never exposed it here.
///
/// Categories can be nested into a parent/child hierarchy: the list is shown
/// flattened in pre-order with each level indented, and a "set parent" action
/// reparents a category (rejecting moves that would create a cycle). Mirrors
/// Kotlin's CategoryScreen + CategoryParentPickerDialog + SetCategoryParent.
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(categoryRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Edit categories')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _promptCreate(context, repo),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: StreamBuilder<List<Category>>(
        stream: repo.watchAll(),
        builder: (context, snap) {
          if (snap.hasError) {
            return _Message(text: 'Failed to load categories: ${snap.error}');
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final categories = snap.data!
              .where((c) => !c.isSystemCategory)
              .toList(growable: false);
          if (categories.isEmpty) {
            return const _Message(
              text: 'You have no categories. Tap the plus button to create '
                  'one for organizing your library.',
            );
          }
          final flattened = _flattenHierarchy(categories);
          return ReorderableListView.builder(
            buildDefaultDragHandles: false,
            itemCount: flattened.length,
            onReorderItem: (oldIndex, newIndex) =>
                _onReorder(repo, flattened, oldIndex, newIndex),
            itemBuilder: (context, i) {
              final entry = flattened[i];
              final c = entry.category;
              return Padding(
                key: ValueKey(c.id),
                padding: EdgeInsets.only(left: entry.depth * 16.0),
                child: ListTile(
                  title: Text(c.name),
                  leading: ReorderableDragStartListener(
                    index: i,
                    child: const Icon(Icons.drag_handle),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.account_tree_outlined),
                        tooltip: 'Set parent category',
                        onPressed: () =>
                            _promptSetParent(context, repo, c, categories),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Rename category',
                        onPressed: () => _promptRename(context, repo, c),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Delete',
                        onPressed: () => _confirmDelete(context, repo, c),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// Sibling-constrained reorder ported from Kotlin's `ReorderCategory`: a drag
  /// only changes order within the dragged category's own parent group, and
  /// reuses that group's existing `sort` slots so unrelated categories are left
  /// untouched. `newIndex` is the post-removal flat-list index.
  Future<void> _onReorder(
    CategoryRepository repo,
    List<_CategoryWithDepth> flattened,
    int oldIndex,
    int newIndex,
  ) async {
    if (newIndex == oldIndex) return;
    final category = flattened[oldIndex].category;
    final all = (await repo.getAll())
        .where((c) => !c.isSystemCategory)
        .toList(growable: false);
    final siblings =
        all.where((c) => c.parentId == category.parentId).toList();
    final currentSiblingIndex = siblings.indexWhere((c) => c.id == category.id);
    if (currentSiblingIndex == -1) return;

    // Translate the flat newIndex into a sibling index by counting how many
    // siblings appear before the target position.
    final flatIndex = all.indexWhere((c) => c.id == category.id);
    final movingForward = newIndex > flatIndex;
    final upper = movingForward
        ? (newIndex + 1).clamp(0, all.length)
        : newIndex.clamp(0, all.length);
    var targetSiblingIndex = all
        .sublist(0, upper)
        .where((c) => c.parentId == category.parentId && c.id != category.id)
        .length;
    targetSiblingIndex = targetSiblingIndex.clamp(0, siblings.length - 1);
    if (currentSiblingIndex == targetSiblingIndex) return;

    siblings.insert(targetSiblingIndex, siblings.removeAt(currentSiblingIndex));

    // Preserve the original sort slots used by this sibling group and
    // redistribute them in the new order.
    final originalSorts = all
        .where((c) => c.parentId == category.parentId)
        .map((c) => c.order)
        .toList()
      ..sort();
    for (var i = 0; i < siblings.length; i++) {
      final order = i < originalSorts.length ? originalSorts[i] : i;
      if (siblings[i].order != order) {
        await repo.update(id: siblings[i].id, order: order);
      }
    }
  }

  Future<void> _promptCreate(
    BuildContext context,
    CategoryRepository repo,
  ) async {
    final existing = await repo.getAll();
    if (!context.mounted) return;
    final taken = {
      for (final c in existing)
        if (!c.isSystemCategory) c.name.toLowerCase(),
    };
    final name = await _promptForName(
      context,
      title: 'Add category',
      confirmLabel: 'Add',
      takenNames: taken,
    );
    if (name == null || name.isEmpty) return;
    // Append at the end, after the highest existing order.
    final maxOrder = existing.fold<int>(0, (m, c) => c.order > m ? c.order : m);
    await repo.insert(name: name, order: maxOrder + 1, flags: 0);
  }

  Future<void> _promptRename(
    BuildContext context,
    CategoryRepository repo,
    Category category,
  ) async {
    final existing = await repo.getAll();
    if (!context.mounted) return;
    final taken = {
      for (final c in existing)
        if (!c.isSystemCategory && c.id != category.id) c.name.toLowerCase(),
    };
    final name = await _promptForName(
      context,
      title: 'Rename category',
      confirmLabel: 'OK',
      initialValue: category.name,
      takenNames: taken,
    );
    if (name == null || name.isEmpty || name == category.name) return;
    await repo.update(id: category.id, name: name);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    CategoryRepository repo,
    Category category,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete category'),
        content: Text('Do you wish to delete the category "${category.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await repo.deleteById(category.id);
    }
  }

  /// Opens the parent picker and applies the choice with cycle protection.
  Future<void> _promptSetParent(
    BuildContext context,
    CategoryRepository repo,
    Category category,
    List<Category> allCategories,
  ) async {
    final result = await showDialog<_ParentPickResult>(
      context: context,
      builder: (ctx) => _ParentPickerDialog(
        target: category,
        allCategories: allCategories,
      ),
    );
    if (result == null) return; // dismissed
    if (!context.mounted) return;
    await _setParent(context, repo, category, result.parentId);
  }

  /// Reparents [category] to [parentId] (null == top level), rejecting moves
  /// that would create a cycle. 1:1 with Kotlin's `SetCategoryParent`.
  Future<void> _setParent(
    BuildContext context,
    CategoryRepository repo,
    Category category,
    int? parentId,
  ) async {
    if (category.isSystemCategory) return; // InvalidTarget
    final sanitized =
        parentId == Category.uncategorizedId ? null : parentId;
    if (sanitized == category.id) {
      _showCycleError(context);
      return;
    }
    if (sanitized != null) {
      final all = await repo.getAll();
      final byId = {for (final c in all) c.id: c};
      // Walk up from the proposed parent; hitting the category (or a
      // pre-existing cycle) means the move is illegal.
      int? cursor = sanitized;
      final visited = <int>{};
      while (cursor != null) {
        if (cursor == category.id || !visited.add(cursor)) {
          if (context.mounted) _showCycleError(context);
          return;
        }
        cursor = byId[cursor]?.parentId;
      }
    }
    await repo.updateParent(id: category.id, parentId: sanitized);
  }

  void _showCycleError(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Can't make a category a child of itself or its descendants",
        ),
      ),
    );
  }

  Future<String?> _promptForName(
    BuildContext context, {
    required String title,
    required String confirmLabel,
    String initialValue = '',
    Set<String> takenNames = const {},
  }) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => _NameDialog(
        title: title,
        confirmLabel: confirmLabel,
        initialValue: initialValue,
        takenNames: takenNames,
      ),
    );
  }
}

/// A category paired with its depth in the hierarchy after flattening (root=0).
class _CategoryWithDepth {
  const _CategoryWithDepth(this.category, this.depth);

  final Category category;
  final int depth;
}

/// Flattens [categories] into a pre-order traversal of the parent/child tree.
/// Cycles, broken parent references, and a parent pointing at the system
/// category are all tolerated by promoting the affected node to a root. Ported
/// from Kotlin's `CategoryTree.flattenedHierarchy`.
List<_CategoryWithDepth> _flattenHierarchy(List<Category> categories) {
  if (categories.isEmpty) return const [];
  final byId = {for (final c in categories) c.id: c};
  final childrenByParent = <int?, List<Category>>{};
  for (final cat in categories) {
    var parent = cat.parentId;
    // A null, system-category, or dangling parent reference is treated as root.
    if (parent != null &&
        (parent == Category.uncategorizedId || !byId.containsKey(parent))) {
      parent = null;
    }
    childrenByParent.putIfAbsent(parent, () => <Category>[]).add(cat);
  }
  // Sort each sibling group by order for deterministic display.
  for (final list in childrenByParent.values) {
    list.sort((a, b) => a.order.compareTo(b.order));
  }

  final result = <_CategoryWithDepth>[];
  final visited = <int>{};
  void dfs(Category node, int depth) {
    if (!visited.add(node.id)) return;
    result.add(_CategoryWithDepth(node, depth));
    for (final child in childrenByParent[node.id] ?? const <Category>[]) {
      dfs(child, depth + 1);
    }
  }

  for (final root in childrenByParent[null] ?? const <Category>[]) {
    dfs(root, 0);
  }
  // Any node orphaned by a cycle is emitted at root depth.
  for (final cat in categories) {
    if (!visited.contains(cat.id)) dfs(cat, 0);
  }
  return result;
}

/// Result of the parent picker: wraps the chosen parent id (null == top level)
/// so a `null` dialog return can be distinguished from "No parent" selected.
class _ParentPickResult {
  const _ParentPickResult(this.parentId);
  final int? parentId;
}

/// Radio picker for a category's parent. Excludes the target and all of its
/// descendants (choosing one would create a cycle) and indents candidates by
/// hierarchy depth. Mirrors Kotlin's `CategoryParentPickerDialog`.
class _ParentPickerDialog extends StatefulWidget {
  const _ParentPickerDialog({
    required this.target,
    required this.allCategories,
  });

  final Category target;
  final List<Category> allCategories;

  @override
  State<_ParentPickerDialog> createState() => _ParentPickerDialogState();
}

class _ParentPickerDialogState extends State<_ParentPickerDialog> {
  late int? _selected = widget.target.parentId;

  /// The target plus every category reachable beneath it.
  Set<int> get _descendantIds {
    final childrenByParent = <int?, List<Category>>{};
    for (final c in widget.allCategories) {
      childrenByParent.putIfAbsent(c.parentId, () => <Category>[]).add(c);
    }
    final collected = <int>{widget.target.id};
    final stack = <int>[widget.target.id];
    while (stack.isNotEmpty) {
      final cursor = stack.removeLast();
      for (final child in childrenByParent[cursor] ?? const <Category>[]) {
        if (collected.add(child.id)) stack.add(child.id);
      }
    }
    return collected;
  }

  @override
  Widget build(BuildContext context) {
    final excluded = _descendantIds;
    final candidates = _flattenHierarchy(
      widget.allCategories
          .where((c) => !excluded.contains(c.id))
          .toList(growable: false),
    );
    return AlertDialog(
      title: const Text('Set parent category'),
      content: SizedBox(
        width: double.maxFinite,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 400),
          child: RadioGroup<int?>(
            groupValue: _selected,
            onChanged: (v) => setState(() => _selected = v),
            child: ListView(
              shrinkWrap: true,
              children: [
                const RadioListTile<int?>(
                  value: null,
                  title: Text('(No parent — top level)'),
                ),
                for (final entry in candidates)
                  Padding(
                    padding: EdgeInsets.only(left: entry.depth * 16.0),
                    child: RadioListTile<int?>(
                      value: entry.category.id,
                      title: Row(
                        children: [
                          if (entry.depth > 0)
                            const Padding(
                              padding: EdgeInsets.only(right: 4),
                              child: Icon(Icons.subdirectory_arrow_right,
                                  size: 18),
                            ),
                          Flexible(child: Text(entry.category.name)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(_ParentPickResult(_selected)),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

/// Create/rename dialog with the same inline validation as Kotlin's
/// CategoryCreateDialog/CategoryRenameDialog: the confirm button stays
/// disabled until the name is non-empty, changed (rename) and unique.
class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.confirmLabel,
    required this.initialValue,
    required this.takenNames,
  });

  final String title;
  final String confirmLabel;
  final String initialValue;
  final Set<String> takenNames;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _name => _controller.text.trim();

  bool get _isDuplicate =>
      _name.isNotEmpty && widget.takenNames.contains(_name.toLowerCase());

  bool get _canConfirm =>
      _name.isNotEmpty && !_isDuplicate && _name != widget.initialValue;

  String? get _supportText {
    if (_name.isEmpty) return '*required';
    if (_isDuplicate) return 'A category with this name already exists!';
    return null;
  }

  void _submit() {
    if (_canConfirm) Navigator.of(context).pop(_name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: 'Name',
          errorText: _supportText,
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _canConfirm ? _submit : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }
}
